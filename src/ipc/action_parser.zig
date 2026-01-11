//! Parse IPC command strings into binding.Action values
//!
//! Commands are simple text:
//!   close
//!   focus next
//!   spawn firefox --new-window
//!   tag 3
//!   layout tile

const std = @import("std");
const mem = std.mem;

const binding = @import("kwm").binding;
const types = @import("kwm").types;
const layout = @import("kwm").layout;
const config = @import("config");

pub const ParseError = error{
    EmptyCommand,
    UnknownCommand,
    MissingArgument,
    InvalidArgument,
    TooManyArguments,
};

/// Parse a command string into an Action
pub fn parse(allocator: mem.Allocator, input: []const u8) ParseError!binding.Action {
    const trimmed = mem.trim(u8, input, " \t\r\n");
    if (trimmed.len == 0) return ParseError.EmptyCommand;

    var iter = mem.splitScalar(u8, trimmed, ' ');
    const cmd = iter.next() orelse return ParseError.EmptyCommand;

    // Nullary commands
    if (mem.eql(u8, cmd, "quit")) return .quit;
    if (mem.eql(u8, cmd, "restart")) return .restart;
    if (mem.eql(u8, cmd, "close")) return .close;
    if (mem.eql(u8, cmd, "popup")) return .show_popup;
    if (mem.eql(u8, cmd, "toggle-floating")) return .toggle_floating;
    if (mem.eql(u8, cmd, "toggle-swallow")) return .toggle_swallow;
    if (mem.eql(u8, cmd, "zoom")) return .zoom;
    if (mem.eql(u8, cmd, "prev-tag")) return .switch_to_previous_tag;
    if (mem.eql(u8, cmd, "fullscreen")) return .{ .toggle_fullscreen = .{} };

    // Direction commands
    if (mem.eql(u8, cmd, "focus")) {
        const dir = parseDirection(iter.next()) orelse return ParseError.MissingArgument;
        return .{ .focus_iter = .{ .direction = dir } };
    }
    if (mem.eql(u8, cmd, "focus-output")) {
        const dir = parseDirection(iter.next()) orelse return ParseError.MissingArgument;
        return .{ .focus_output_iter = .{ .direction = dir } };
    }
    if (mem.eql(u8, cmd, "send-to-output")) {
        const dir = parseDirection(iter.next()) orelse return ParseError.MissingArgument;
        return .{ .send_to_output = .{ .direction = dir } };
    }
    if (mem.eql(u8, cmd, "swap")) {
        const dir = parseDirection(iter.next()) orelse return ParseError.MissingArgument;
        return .{ .swap = .{ .direction = dir } };
    }

    // Layout command
    if (mem.eql(u8, cmd, "layout")) {
        const layout_name = iter.next() orelse return ParseError.MissingArgument;
        const layout_type = parseLayout(layout_name) orelse return ParseError.InvalidArgument;
        return .{ .switch_layout = .{ .layout = layout_type } };
    }

    // Mode command
    if (mem.eql(u8, cmd, "mode")) {
        const mode_name = iter.next() orelse return ParseError.MissingArgument;
        const mode = parseMode(mode_name) orelse return ParseError.InvalidArgument;
        return .{ .switch_mode = .{ .mode = mode } };
    }

    // Tag commands
    if (mem.eql(u8, cmd, "tag")) {
        const tag_str = iter.next() orelse return ParseError.MissingArgument;
        const tag = std.fmt.parseInt(u5, tag_str, 10) catch return ParseError.InvalidArgument;
        return .{ .set_output_tag = .{ .tag = @as(u32, 1) << tag } };
    }
    if (mem.eql(u8, cmd, "window-tag")) {
        const tag_str = iter.next() orelse return ParseError.MissingArgument;
        const tag = std.fmt.parseInt(u5, tag_str, 10) catch return ParseError.InvalidArgument;
        return .{ .set_window_tag = .{ .tag = @as(u32, 1) << tag } };
    }
    if (mem.eql(u8, cmd, "tag-toggle")) {
        const tag_str = iter.next() orelse return ParseError.MissingArgument;
        const tag = std.fmt.parseInt(u5, tag_str, 10) catch return ParseError.InvalidArgument;
        return .{ .toggle_output_tag = .{ .mask = @as(u32, 1) << tag } };
    }
    if (mem.eql(u8, cmd, "window-tag-toggle")) {
        const tag_str = iter.next() orelse return ParseError.MissingArgument;
        const tag = std.fmt.parseInt(u5, tag_str, 10) catch return ParseError.InvalidArgument;
        return .{ .toggle_window_tag = .{ .mask = @as(u32, 1) << tag } };
    }

    // Spawn commands - collect remaining args
    if (mem.eql(u8, cmd, "spawn")) {
        return parseSpawn(allocator, &iter) orelse ParseError.MissingArgument;
    }
    if (mem.eql(u8, cmd, "spawn-shell")) {
        // Rest of line is the shell command
        const rest = iter.rest();
        if (rest.len == 0) return ParseError.MissingArgument;
        return .{ .spawn_shell = .{ .cmd = rest } };
    }

    return ParseError.UnknownCommand;
}

fn parseDirection(arg: ?[]const u8) ?types.Direction {
    const s = arg orelse return null;
    if (mem.eql(u8, s, "next") or mem.eql(u8, s, "forward")) return .forward;
    if (mem.eql(u8, s, "prev") or mem.eql(u8, s, "reverse")) return .reverse;
    return null;
}

fn parseLayout(arg: []const u8) ?layout.Type {
    if (mem.eql(u8, arg, "tile")) return .tile;
    if (mem.eql(u8, arg, "monocle")) return .monocle;
    if (mem.eql(u8, arg, "scroller")) return .scroller;
    if (mem.eql(u8, arg, "float")) return .float;
    return null;
}

fn parseMode(arg: []const u8) ?config.Mode {
    inline for (@typeInfo(config.Mode).@"enum".fields) |field| {
        if (mem.eql(u8, arg, field.name)) {
            return @enumFromInt(field.value);
        }
    }
    return null;
}

fn parseSpawn(allocator: mem.Allocator, iter: *mem.SplitIterator(u8, .scalar)) ?binding.Action {
    var args: std.ArrayListUnmanaged([]const u8) = .empty;

    while (iter.next()) |arg| {
        args.append(allocator, arg) catch return null;
    }

    if (args.items.len == 0) return null;

    return .{ .spawn = .{ .argv = args.toOwnedSlice(allocator) catch return null } };
}

// Tests
test "parse nullary commands" {
    const allocator = std.testing.allocator;

    try std.testing.expectEqual(binding.Action.quit, try parse(allocator, "quit"));
    try std.testing.expectEqual(binding.Action.close, try parse(allocator, "close"));
    try std.testing.expectEqual(binding.Action.show_popup, try parse(allocator, "popup"));
    try std.testing.expectEqual(binding.Action.toggle_floating, try parse(allocator, "toggle-floating"));
}

test "parse direction commands" {
    const allocator = std.testing.allocator;

    const focus_next = try parse(allocator, "focus next");
    try std.testing.expectEqual(types.Direction.forward, focus_next.focus_iter.direction);

    const focus_prev = try parse(allocator, "focus prev");
    try std.testing.expectEqual(types.Direction.reverse, focus_prev.focus_iter.direction);
}

test "parse tag commands" {
    const allocator = std.testing.allocator;

    const tag3 = try parse(allocator, "tag 3");
    try std.testing.expectEqual(@as(u32, 1 << 3), tag3.set_output_tag.tag);
}

test "parse errors" {
    const allocator = std.testing.allocator;

    try std.testing.expectError(ParseError.EmptyCommand, parse(allocator, ""));
    try std.testing.expectError(ParseError.UnknownCommand, parse(allocator, "foobar"));
    try std.testing.expectError(ParseError.MissingArgument, parse(allocator, "focus"));
    try std.testing.expectError(ParseError.MissingArgument, parse(allocator, "tag"));
}
