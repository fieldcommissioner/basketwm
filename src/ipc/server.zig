//! Unix socket IPC server for basketholder
//!
//! Listens on $XDG_RUNTIME_DIR/basket.sock for commands.
//! Each connection can send newline-delimited commands.

const std = @import("std");
const posix = std.posix;
const net = std.net;
const mem = std.mem;
const log = std.log.scoped(.ipc);

const utils = @import("utils");
const kwm = @import("kwm");
const action_parser = @import("action_parser.zig");

const Self = @This();

socket_fd: posix.fd_t,
socket_path: []const u8,
allocator: mem.Allocator,

/// Initialize the IPC server
pub fn init(allocator: mem.Allocator) !Self {
    const socket_path = try getSocketPath(allocator);
    errdefer allocator.free(socket_path);

    // Remove stale socket if it exists
    posix.unlink(socket_path) catch |err| {
        if (err != error.FileNotFound) {
            log.warn("failed to unlink stale socket: {}", .{err});
        }
    };

    // Create unix socket
    const socket_fd = try posix.socket(posix.AF.UNIX, posix.SOCK.STREAM | posix.SOCK.NONBLOCK | posix.SOCK.CLOEXEC, 0);
    errdefer posix.close(socket_fd);

    // Bind to path
    var addr: posix.sockaddr.un = .{ .path = undefined, .family = posix.AF.UNIX };
    @memset(&addr.path, 0);
    const path_len = @min(socket_path.len, addr.path.len - 1);
    @memcpy(addr.path[0..path_len], socket_path[0..path_len]);

    try posix.bind(socket_fd, @ptrCast(&addr), @sizeOf(posix.sockaddr.un));
    try posix.listen(socket_fd, 5);

    log.info("listening on {s}", .{socket_path});

    return .{
        .socket_fd = socket_fd,
        .socket_path = socket_path,
        .allocator = allocator,
    };
}

pub fn deinit(self: *Self) void {
    posix.close(self.socket_fd);
    posix.unlink(self.socket_path) catch {};
    self.allocator.free(self.socket_path);
}

/// Get the file descriptor for polling
pub fn getFd(self: *const Self) posix.fd_t {
    return self.socket_fd;
}

/// Handle incoming data on the socket
/// Call this when poll indicates the socket is readable
pub fn handleEvent(self: *Self) void {
    // Accept new connections (non-blocking)
    while (true) {
        const client_fd = posix.accept(self.socket_fd, null, null, posix.SOCK.NONBLOCK | posix.SOCK.CLOEXEC) catch |err| {
            if (err == error.WouldBlock) break;
            log.warn("accept failed: {}", .{err});
            break;
        };

        self.handleClient(client_fd);
        posix.close(client_fd);
    }
}

fn handleClient(self: *Self, client_fd: posix.fd_t) void {
    var buf: [4096]u8 = undefined;

    const n = posix.read(client_fd, &buf) catch |err| {
        log.warn("read failed: {}", .{err});
        return;
    };

    if (n == 0) return;

    const data = buf[0..n];

    // Process each line as a command
    var lines = mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;

        self.processCommand(trimmed, client_fd);
    }
}

fn processCommand(self: *Self, cmd: []const u8, client_fd: posix.fd_t) void {
    log.debug("command: {s}", .{cmd});

    // Handle meta commands
    if (mem.eql(u8, cmd, "list")) {
        self.sendResponse(client_fd, listCommands());
        return;
    }

    // Parse action
    const action = action_parser.parse(self.allocator, cmd) catch |err| {
        const msg = switch (err) {
            action_parser.ParseError.EmptyCommand => "error: empty command\n",
            action_parser.ParseError.UnknownCommand => "error: unknown command\n",
            action_parser.ParseError.MissingArgument => "error: missing argument\n",
            action_parser.ParseError.InvalidArgument => "error: invalid argument\n",
            action_parser.ParseError.TooManyArguments => "error: too many arguments\n",
        };
        self.sendResponse(client_fd, msg);
        return;
    };

    // Queue action to current seat
    const context = kwm.Context.get();
    if (context.current_seat) |seat| {
        seat.unhandled_actions.append(self.allocator, action) catch |err| {
            log.err("failed to queue action: {}", .{err});
            self.sendResponse(client_fd, "error: failed to queue action\n");
            return;
        };

        // Trigger a manage sequence so the action gets processed
        context.rwm.manageDirty();

        self.sendResponse(client_fd, "ok\n");
    } else {
        self.sendResponse(client_fd, "error: no seat available\n");
    }
}

fn sendResponse(_: *Self, client_fd: posix.fd_t, msg: []const u8) void {
    _ = posix.write(client_fd, msg) catch {};
}

fn listCommands() []const u8 {
    return
        \\quit           - Exit basket
        \\close          - Close focused window
        \\popup          - Show popup menu
        \\toggle-floating - Toggle focused window floating
        \\toggle-swallow - Toggle focused window swallow
        \\zoom           - Move focused window to head
        \\prev-tag       - Switch to previous tag
        \\fullscreen     - Toggle fullscreen
        \\focus <next|prev> - Focus next/previous window
        \\focus-output <next|prev> - Focus next/previous output
        \\send-to-output <next|prev> - Send window to output
        \\swap <next|prev> - Swap window position
        \\layout <tile|monocle|scroller|float> - Switch layout
        \\mode <name>    - Switch to mode
        \\tag <n>        - Switch output to tag n
        \\window-tag <n> - Set window tag to n
        \\tag-toggle <n> - Toggle output tag n
        \\window-tag-toggle <n> - Toggle window tag n
        \\spawn <args...> - Spawn a program
        \\spawn-shell <cmd> - Spawn via shell
        \\list           - Show this help
        \\
    ;
}

fn getSocketPath(allocator: mem.Allocator) ![]const u8 {
    // Try XDG_RUNTIME_DIR first
    if (std.posix.getenv("XDG_RUNTIME_DIR")) |runtime_dir| {
        return std.fs.path.join(allocator, &.{ runtime_dir, "basket.sock" });
    }

    // Fallback to /tmp/basket-$UID.sock
    const uid = std.os.linux.getuid();
    return std.fmt.allocPrint(allocator, "/tmp/basket-{}.sock", .{uid});
}
