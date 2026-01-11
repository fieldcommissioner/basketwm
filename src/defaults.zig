//! Basket default keybindings
//!
//! Sane defaults for a newcomer-friendly tiling window manager.
//! These work out of the box with zero configuration.
//!
//! Ricers can override via basket.zon, newcomers can extend via delta.zon chords.

const xkb = @import("xkbcommon");
const Keysym = xkb.Keysym;
const wayland = @import("wayland");
const river = wayland.client.river;

const kwm = @import("kwm");
const binding = kwm.binding;
const layout = kwm.layout;
const types = kwm.types;

// Modifier shortcuts
const Super: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.mod4);
const Shift: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.shift);
const Ctrl: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.ctrl);
const Alt: u32 = @intFromEnum(river.SeatV1.Modifiers.Enum.mod1);

const Button = struct {
    const left = 0x110;
    const right = 0x111;
    const middle = 0x112;
};

/// Default keyboard bindings - sane out-of-box experience
pub const xkb_bindings = [_]XkbBinding{
    // === Essential ===
    .{ .keysym = Keysym.q, .modifiers = Super | Shift, .action = .quit },
    .{ .keysym = Keysym.c, .modifiers = Super | Shift, .action = .close },

    // === Focus navigation ===
    .{ .keysym = Keysym.j, .modifiers = Super, .action = .{ .focus_iter = .{ .direction = .forward } } },
    .{ .keysym = Keysym.k, .modifiers = Super, .action = .{ .focus_iter = .{ .direction = .reverse } } },

    // === Window manipulation ===
    .{ .keysym = Keysym.j, .modifiers = Super | Shift, .action = .{ .swap = .{ .direction = .forward } } },
    .{ .keysym = Keysym.k, .modifiers = Super | Shift, .action = .{ .swap = .{ .direction = .reverse } } },
    .{ .keysym = Keysym.Return, .modifiers = Super, .action = .zoom },
    .{ .keysym = Keysym.space, .modifiers = Super, .action = .toggle_floating },
    .{ .keysym = Keysym.f, .modifiers = Super | Shift, .action = .{ .toggle_fullscreen = .{} } },

    // === Layout switching ===
    .{ .keysym = Keysym.t, .modifiers = Super, .action = .{ .switch_layout = .{ .layout = .tile } } },
    .{ .keysym = Keysym.m, .modifiers = Super, .action = .{ .switch_layout = .{ .layout = .monocle } } },
    .{ .keysym = Keysym.s, .modifiers = Super, .action = .{ .switch_layout = .{ .layout = .scroller } } },

    // === Output navigation ===
    .{ .keysym = Keysym.period, .modifiers = Super, .action = .{ .focus_output_iter = .{ .direction = .forward } } },
    .{ .keysym = Keysym.comma, .modifiers = Super, .action = .{ .focus_output_iter = .{ .direction = .reverse } } },
    .{ .keysym = Keysym.period, .modifiers = Super | Shift, .action = .{ .send_to_output = .{ .direction = .forward } } },
    .{ .keysym = Keysym.comma, .modifiers = Super | Shift, .action = .{ .send_to_output = .{ .direction = .reverse } } },

    // === Tags ===
    .{ .keysym = Keysym.Tab, .modifiers = Super, .action = .switch_to_previous_tag },
    .{ .keysym = Keysym.@"0", .modifiers = Super, .action = .{ .set_output_tag = .{ .tag = 0xffffffff } } },

    // === Delta popup (chord entry point) ===
    .{ .keysym = Keysym.d, .modifiers = Super, .action = .show_popup },
} ++ tagBindings(9);

/// Default pointer bindings
pub const pointer_bindings = [_]PointerBinding{
    .{ .button = Button.left, .modifiers = Super, .action = .pointer_move },
    .{ .button = Button.right, .modifiers = Super, .action = .pointer_resize },
};

/// Generate tag bindings for 1-N
fn tagBindings(comptime n: usize) [n * 4]XkbBinding {
    var bindings: [n * 4]XkbBinding = undefined;
    for (0..n) |i| {
        // Super+N = view tag N
        bindings[i * 4] = .{
            .keysym = Keysym.@"1" + i,
            .modifiers = Super,
            .action = .{ .set_output_tag = .{ .tag = 1 << i } },
        };
        // Super+Shift+N = move window to tag N
        bindings[i * 4 + 1] = .{
            .keysym = Keysym.@"1" + i,
            .modifiers = Super | Shift,
            .action = .{ .set_window_tag = .{ .tag = 1 << i } },
        };
        // Super+Ctrl+N = toggle tag N visibility
        bindings[i * 4 + 2] = .{
            .keysym = Keysym.@"1" + i,
            .modifiers = Super | Ctrl,
            .action = .{ .toggle_output_tag = .{ .mask = 1 << i } },
        };
        // Super+Ctrl+Shift+N = toggle window tag N
        bindings[i * 4 + 3] = .{
            .keysym = Keysym.@"1" + i,
            .modifiers = Super | Ctrl | Shift,
            .action = .{ .toggle_window_tag = .{ .mask = 1 << i } },
        };
    }
    return bindings;
}

// Type aliases matching config.zig structure
pub const XkbBinding = struct {
    keysym: u32,
    modifiers: u32,
    action: binding.Action,
    mode: Mode = .default,
    event: river.XkbBindingV1.Event = .pressed,
};

pub const PointerBinding = struct {
    button: u32,
    modifiers: u32,
    action: binding.Action,
    mode: Mode = .default,
    event: river.PointerBindingV1.Event = .pressed,
};

pub const Mode = enum {
    lock,
    default,
};

// === Default visual/behavior settings ===

pub const border_width: i32 = 3;
pub const border_color = .{
    .focus = 0x88c0d0ff, // Nord frost
    .unfocus = 0x4c566aff, // Nord polar night
    .urgent = 0xbf616aff, // Nord aurora red
};

pub const default_layout: layout.Type = .tile;

pub const tile_layout = kwm.layout.tile{
    .nmaster = 1,
    .mfact = 0.55,
    .inner_gap = 8,
    .outer_gap = 8,
    .master_location = .left,
};

pub const monocle_layout = kwm.layout.monocle{
    .gap = 0,
};

pub const scroller_layout = kwm.layout.scroller{
    .mfact = 0.6,
    .inner_gap = 12,
    .outer_gap = 8,
    .snap_to_left = false,
};

pub const sloppy_focus = false;
pub const repeat_rate = 50;
pub const repeat_delay = 300;
