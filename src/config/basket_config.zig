//! basket.zon parser - ricer combo configuration
//!
//! Allows runtime keybinding customization:
//!
//! .{
//!     // Remove default bindings
//!     .unbind = .{
//!         "Super+P",
//!     },
//!
//!     // Add or override bindings
//!     .bind = .{
//!         .{ "Super+Return", "spawn alacritty" },
//!         .{ "Super+Shift+Return", "spawn ghostty" },
//!         .{ "Super+B", "spawn firefox" },
//!     },
//!
//!     // Ignore all defaults (CBT mode)
//!     .disable_defaults = false,
//! }

const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.basket_config);

const wayland = @import("wayland");
const river = wayland.client.river;
const xkb = @import("xkbcommon");
const Keysym = xkb.Keysym;

const kwm = @import("kwm");
const binding = kwm.binding;
const ipc = @import("ipc");

pub const BasketConfig = struct {
    allocator: mem.Allocator,
    disable_defaults: bool = false,
    unbinds: std.ArrayListUnmanaged(UnbindEntry) = .empty,
    binds: std.ArrayListUnmanaged(BindEntry) = .empty,

    pub fn deinit(self: *BasketConfig) void {
        for (self.unbinds.items) |entry| {
            self.allocator.free(entry.combo);
        }
        self.unbinds.deinit(self.allocator);

        for (self.binds.items) |entry| {
            self.allocator.free(entry.combo);
            self.allocator.free(entry.action);
        }
        self.binds.deinit(self.allocator);
    }
};

pub const UnbindEntry = struct {
    combo: []const u8,
    keysym: u32,
    modifiers: u32,
};

pub const BindEntry = struct {
    combo: []const u8,
    keysym: u32,
    modifiers: u32,
    action: []const u8,
    parsed_action: ?binding.Action = null,
};

/// Load basket.zon from config directory
pub fn load(allocator: mem.Allocator, config_dir: []const u8) !BasketConfig {
    const path = try std.fs.path.join(allocator, &.{ config_dir, "basket.zon" });
    defer allocator.free(path);

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            log.info("no basket.zon found, using defaults only", .{});
            return BasketConfig{ .allocator = allocator };
        }
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 64);
    defer allocator.free(content);

    return parse(allocator, content);
}

fn parse(allocator: mem.Allocator, content: []const u8) !BasketConfig {
    var config = BasketConfig{ .allocator = allocator };

    var lines = mem.splitScalar(u8, content, '\n');
    var in_unbind = false;
    var in_bind = false;

    while (lines.next()) |line| {
        const trimmed = mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (mem.startsWith(u8, trimmed, "//")) continue;

        // Detect sections
        if (mem.indexOf(u8, trimmed, ".unbind")) |_| {
            in_unbind = true;
            in_bind = false;
            continue;
        }
        if (mem.indexOf(u8, trimmed, ".bind")) |_| {
            in_bind = true;
            in_unbind = false;
            continue;
        }
        if (mem.indexOf(u8, trimmed, ".disable_defaults")) |_| {
            if (mem.indexOf(u8, trimmed, "true")) |_| {
                config.disable_defaults = true;
            }
            continue;
        }

        // End of section
        if (mem.eql(u8, trimmed, "},")) {
            in_unbind = false;
            in_bind = false;
            continue;
        }

        // Parse entries
        if (in_unbind) {
            if (parseUnbindLine(allocator, trimmed)) |entry| {
                try config.unbinds.append(allocator, entry);
            }
        } else if (in_bind) {
            if (parseBindLine(allocator, trimmed)) |entry| {
                try config.binds.append(allocator, entry);
            }
        }
    }

    log.info("loaded basket.zon: {} unbinds, {} binds, disable_defaults={}", .{
        config.unbinds.items.len,
        config.binds.items.len,
        config.disable_defaults,
    });

    return config;
}

fn parseUnbindLine(allocator: mem.Allocator, line: []const u8) ?UnbindEntry {
    // Parse: "Super+P",
    const start = mem.indexOf(u8, line, "\"") orelse return null;
    const end = mem.lastIndexOf(u8, line, "\"") orelse return null;
    if (end <= start + 1) return null;

    const combo = line[start + 1 .. end];
    const parsed = parseCombo(combo) orelse return null;

    return UnbindEntry{
        .combo = allocator.dupe(u8, combo) catch return null,
        .keysym = parsed.keysym,
        .modifiers = parsed.modifiers,
    };
}

fn parseBindLine(allocator: mem.Allocator, line: []const u8) ?BindEntry {
    // Parse: .{ "Super+Return", "spawn alacritty" },
    var quotes = mem.splitScalar(u8, line, '"');
    _ = quotes.next(); // skip before first quote

    const combo = quotes.next() orelse return null;
    _ = quotes.next(); // skip between quotes

    const action = quotes.next() orelse return null;

    const parsed = parseCombo(combo) orelse return null;

    // Parse the action string using IPC parser
    var entry = BindEntry{
        .combo = allocator.dupe(u8, combo) catch return null,
        .keysym = parsed.keysym,
        .modifiers = parsed.modifiers,
        .action = allocator.dupe(u8, action) catch return null,
    };

    // Try to parse action
    entry.parsed_action = ipc.action_parser.parse(allocator, action) catch null;

    return entry;
}

const ParsedCombo = struct {
    keysym: u32,
    modifiers: u32,
};

fn parseCombo(combo: []const u8) ?ParsedCombo {
    var modifiers: u32 = 0;
    var keysym: u32 = 0;

    var parts = mem.splitScalar(u8, combo, '+');
    while (parts.next()) |part| {
        const trimmed = mem.trim(u8, part, " ");
        if (trimmed.len == 0) continue;

        // Check modifiers
        if (mem.eql(u8, trimmed, "Super") or mem.eql(u8, trimmed, "Mod4")) {
            modifiers |= @intFromEnum(river.SeatV1.Modifiers.Enum.mod4);
        } else if (mem.eql(u8, trimmed, "Shift")) {
            modifiers |= @intFromEnum(river.SeatV1.Modifiers.Enum.shift);
        } else if (mem.eql(u8, trimmed, "Ctrl") or mem.eql(u8, trimmed, "Control")) {
            modifiers |= @intFromEnum(river.SeatV1.Modifiers.Enum.ctrl);
        } else if (mem.eql(u8, trimmed, "Alt") or mem.eql(u8, trimmed, "Mod1")) {
            modifiers |= @intFromEnum(river.SeatV1.Modifiers.Enum.mod1);
        } else {
            // Must be the key
            keysym = parseKeysym(trimmed) orelse return null;
        }
    }

    if (keysym == 0) return null;

    return ParsedCombo{
        .keysym = keysym,
        .modifiers = modifiers,
    };
}

fn parseKeysym(key: []const u8) ?u32 {
    // Single character
    if (key.len == 1) {
        const c = key[0];
        return switch (c) {
            'a'...'z' => Keysym.a + (c - 'a'),
            'A'...'Z' => Keysym.a + (c - 'A'), // treat as lowercase
            '0'...'9' => Keysym.@"0" + (c - '0'),
            else => null,
        };
    }

    // Named keys
    if (mem.eql(u8, key, "Return") or mem.eql(u8, key, "Enter")) return Keysym.Return;
    if (mem.eql(u8, key, "Space")) return Keysym.space;
    if (mem.eql(u8, key, "Tab")) return Keysym.Tab;
    if (mem.eql(u8, key, "Escape") or mem.eql(u8, key, "Esc")) return Keysym.Escape;
    if (mem.eql(u8, key, "BackSpace")) return Keysym.BackSpace;
    if (mem.eql(u8, key, "Delete")) return Keysym.Delete;
    if (mem.eql(u8, key, "Home")) return Keysym.Home;
    if (mem.eql(u8, key, "End")) return Keysym.End;
    if (mem.eql(u8, key, "Page_Up")) return Keysym.Page_Up;
    if (mem.eql(u8, key, "Page_Down")) return Keysym.Page_Down;
    if (mem.eql(u8, key, "Left")) return Keysym.Left;
    if (mem.eql(u8, key, "Right")) return Keysym.Right;
    if (mem.eql(u8, key, "Up")) return Keysym.Up;
    if (mem.eql(u8, key, "Down")) return Keysym.Down;

    // F keys
    if (key.len >= 2 and key[0] == 'F') {
        const num = std.fmt.parseInt(u32, key[1..], 10) catch return null;
        if (num >= 1 and num <= 12) {
            return Keysym.F1 + (num - 1);
        }
    }

    return null;
}

/// Check if a binding should be excluded based on unbind list
pub fn shouldUnbind(config: *const BasketConfig, keysym: u32, modifiers: u32) bool {
    for (config.unbinds.items) |entry| {
        if (entry.keysym == keysym and entry.modifiers == modifiers) {
            return true;
        }
    }
    return false;
}
