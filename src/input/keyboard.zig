//! Keyboard input handling for Deltas
//!
//! Manages:
//!   - wl_keyboard binding and events
//!   - Keymap (xkb) for symbol translation
//!   - Key routing to Navigator

const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;

const tree = @import("../tree/navigation.zig");

pub const KeyboardHandler = struct {
    seat: *wl.Seat,
    keyboard: ?*wl.Keyboard = null,
    navigator: *tree.Navigator,

    // Callback for UI updates
    on_nav_action: ?*const fn (tree.NavAction) void = null,

    pub fn init(seat: *wl.Seat, navigator: *tree.Navigator) KeyboardHandler {
        return .{
            .seat = seat,
            .navigator = navigator,
        };
    }

    pub fn setup(self: *KeyboardHandler) !void {
        // Get keyboard from seat
        self.keyboard = self.seat.getKeyboard() catch return error.NoKeyboard;

        // Set up keyboard listener
        self.keyboard.?.setListener(*KeyboardHandler, keyboardListener, self);
    }

    pub fn deinit(self: *KeyboardHandler) void {
        if (self.keyboard) |kb| {
            kb.release();
        }
    }

    fn keyboardListener(keyboard: *wl.Keyboard, event: wl.Keyboard.Event, self: *KeyboardHandler) void {
        _ = keyboard;

        switch (event) {
            .keymap => |keymap| {
                // TODO: Set up xkbcommon for proper key translation
                // For now we'll use raw keycodes
                _ = keymap;
                std.debug.print("[keyboard] keymap received\n", .{});
            },
            .enter => |enter| {
                _ = enter;
                std.debug.print("[keyboard] enter (focus gained)\n", .{});
            },
            .leave => |leave| {
                _ = leave;
                std.debug.print("[keyboard] leave (focus lost)\n", .{});
            },
            .key => |key| {
                // Only handle key press, not release
                if (key.state == .pressed) {
                    self.handleKeyPress(key.key);
                }
            },
            .modifiers => |mods| {
                // TODO: Track modifier state for Shift, Ctrl, etc.
                _ = mods;
            },
            .repeat_info => |info| {
                _ = info;
                // Key repeat settings - use for sticky modes
            },
        }
    }

    fn handleKeyPress(self: *KeyboardHandler, keycode: u32) void {
        // Linux evdev keycodes are offset by 8 from X11/Wayland
        // For now, do simple ASCII mapping for letters
        // TODO: Use xkbcommon for proper translation

        const key: ?u8 = keycodeToAscii(keycode);

        if (key) |k| {
            std.debug.print("[keyboard] key press: '{c}' (code {})\n", .{ k, keycode });

            // Route to navigator
            if (self.navigator.handleKey(k)) |action| {
                std.debug.print("[keyboard] nav action: {}\n", .{action});

                // Notify UI
                if (self.on_nav_action) |callback| {
                    callback(action);
                }
            }
        } else {
            std.debug.print("[keyboard] unmapped keycode: {}\n", .{keycode});
        }
    }
};

/// Simple keycode to ASCII mapping (evdev keycodes)
/// TODO: Replace with xkbcommon for proper internationalization
fn keycodeToAscii(keycode: u32) ?u8 {
    // evdev keycodes (add 8 for X11/Wayland offset already applied by compositor)
    return switch (keycode) {
        // Escape
        1 => 27, // ESC

        // Number row
        2 => '1',
        3 => '2',
        4 => '3',
        5 => '4',
        6 => '5',
        7 => '6',
        8 => '7',
        9 => '8',
        10 => '9',
        11 => '0',
        12 => '-',
        13 => '=',

        // Top row (qwerty)
        16 => 'q',
        17 => 'w',
        18 => 'e',
        19 => 'r',
        20 => 't',
        21 => 'y',
        22 => 'u',
        23 => 'i',
        24 => 'o',
        25 => 'p',
        26 => '[',
        27 => ']',

        // Home row
        30 => 'a',
        31 => 's',
        32 => 'd',
        33 => 'f',
        34 => 'g',
        35 => 'h',
        36 => 'j',
        37 => 'k',
        38 => 'l',

        // Bottom row
        44 => 'z',
        45 => 'x',
        46 => 'c',
        47 => 'v',
        48 => 'b',
        49 => 'n',
        50 => 'm',
        51 => ',',
        52 => '.',

        else => null,
    };
}

test "keycode mapping" {
    try std.testing.expectEqual(@as(?u8, 'a'), keycodeToAscii(30));
    try std.testing.expectEqual(@as(?u8, 27), keycodeToAscii(1)); // ESC
    try std.testing.expectEqual(@as(?u8, null), keycodeToAscii(999));
}
