//! Basket popup menu
//!
//! Integrates deltas-style which-key popup with kwm's window management.
//! Triggered by leader key, dispatches actions to kwm internals.

const std = @import("std");
const log = std.log.scoped(.popup);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const utils = @import("utils");
const kwm = @import("kwm");
const render = @import("render/mod.zig");
const surface_mod = @import("surface/layer.zig");
const tree = @import("tree/navigation.zig");
pub const zon_config = @import("config/loader.zig");
const settings_mod = @import("config/settings.zig");

// Global popup instance
var global_popup: ?*Popup = null;

pub const Popup = struct {
    allocator: std.mem.Allocator,

    // Wayland objects
    compositor: *wl.Compositor,
    layer_shell: *zwlr.LayerShellV1,
    shm: *wl.Shm,
    seat: ?*wl.Seat = null,
    keyboard: ?*wl.Keyboard = null,

    // Menu state
    layer_surface: ?surface_mod.LayerSurface = null,
    navigator: ?tree.Navigator = null,
    menu_root: ?*const tree.Node = null,
    config: ?zon_config.Config = null,
    settings: ?settings_mod.Settings = null,

    // Visibility
    visible: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        compositor: *wl.Compositor,
        layer_shell: *zwlr.LayerShellV1,
        shm: *wl.Shm,
    ) !*Popup {
        const popup = try allocator.create(Popup);
        popup.* = .{
            .allocator = allocator,
            .compositor = compositor,
            .layer_shell = layer_shell,
            .shm = shm,
        };

        global_popup = popup;
        log.info("popup initialized", .{});

        return popup;
    }

    pub fn get() ?*Popup {
        return global_popup;
    }

    pub fn setSeat(self: *Popup, seat: *wl.Seat) void {
        self.seat = seat;
        log.debug("seat set: {*}", .{seat});
    }

    pub fn loadConfig(self: *Popup, config_dir: []const u8) void {
        // Load settings from config.zon (theme, font, etc)
        if (zon_config.loadSettings(self.allocator, config_dir)) |s| {
            self.settings = s;
            log.info("loaded settings: font={s} size={}", .{ s.font.family, s.font.size });
        } else |err| {
            log.warn("failed to load settings: {}, using defaults", .{err});
        }

        // Load .zon config (delta tree)
        if (zon_config.load(self.allocator, config_dir)) |cfg| {
            self.config = cfg;
            if (cfg.root) |root| {
                self.menu_root = root;
                log.info("loaded config from {s}", .{config_dir});
            }
        } else |err| {
            log.warn("failed to load config: {}, using fallback", .{err});
            // Use built-in fallback
            self.menu_root = getDefaultMenu(self.allocator);
        }
    }

    pub fn show(self: *Popup) !void {
        if (self.visible) return;

        log.debug("showing popup", .{});

        // Create layer surface on first show
        if (self.layer_surface == null) {
            if (self.settings) |s| {
                // Use loaded settings for theme, font, and position
                log.info("creating layer surface with font: {s} size={} pos={s}", .{ s.font.family, s.font.size, @tagName(s.position) });
                const theme = render.Theme.fromSettings(s.theme);
                self.layer_surface = surface_mod.LayerSurface.initWithFont(
                    self.compositor,
                    self.layer_shell,
                    self.shm,
                    theme,
                    s.font.family,
                    s.font.size,
                    s.position,
                );
            } else {
                log.info("creating layer surface with defaults (no settings)", .{});
                self.layer_surface = surface_mod.LayerSurface.init(
                    self.compositor,
                    self.layer_shell,
                    self.shm,
                );
            }
            try self.layer_surface.?.create();
        }

        // Set up keyboard listener
        if (self.seat != null and self.keyboard == null) {
            self.keyboard = self.seat.?.getKeyboard() catch null;
            if (self.keyboard) |kb| {
                kb.setListener(*Popup, keyboardListener, self);
                log.debug("keyboard listener attached", .{});
            }
        }

        // Show menu
        if (self.menu_root) |root| {
            if (self.navigator == null) {
                self.navigator = tree.Navigator.init(self.allocator, root);
            } else {
                // Reset to root
                self.navigator.?.current = root;
            }
            self.layer_surface.?.showMenu(root);
        }

        self.visible = true;
    }

    pub fn hide(self: *Popup) void {
        if (!self.visible) return;

        log.debug("hiding popup", .{});

        if (self.layer_surface) |*ls| {
            ls.destroy();
            self.layer_surface = null;
        }

        // Release keyboard (will be re-acquired on next show)
        if (self.keyboard) |kb| {
            kb.release();
            self.keyboard = null;
        }

        self.visible = false;
    }

    fn keyboardListener(keyboard: *wl.Keyboard, event: wl.Keyboard.Event, self: *Popup) void {
        _ = keyboard;

        switch (event) {
            .keymap => |_| {
                log.debug("keymap received", .{});
            },
            .enter => |_| {
                log.debug("keyboard enter (focus gained)", .{});
            },
            .leave => |_| {
                log.debug("keyboard leave (focus lost)", .{});
                // Auto-hide on focus loss
                self.hide();
            },
            .key => |key| {
                if (key.state == .pressed) {
                    self.handleKeyPress(key.key);
                }
            },
            .modifiers => |_| {},
            .repeat_info => |_| {},
        }
    }

    fn handleKeyPress(self: *Popup, keycode: u32) void {
        const key: ?u8 = keycodeToAscii(keycode);

        if (key) |k| {
            log.debug("key press: '{c}' (code {})", .{k, keycode});

            if (self.navigator) |*nav| {
                if (nav.handleKey(k)) |nav_action| {
                    self.handleNavAction(nav_action);
                }
            }
        } else {
            log.debug("unmapped keycode: {}", .{keycode});
        }
    }

    fn handleNavAction(self: *Popup, nav_action: tree.NavAction) void {
        const context = kwm.Context.get();

        switch (nav_action) {
            .execute => |node| {
                self.executeAction(node, context);
                // Keep popup open for sticky/repeat actions
            },
            .execute_and_close => |node| {
                self.hide();
                self.executeAction(node, context);
            },
            .show_menu => |node| {
                if (self.layer_surface) |*ls| {
                    ls.showMenu(node);
                }
            },
            .close => {
                self.hide();
            },
        }
    }

    fn executeAction(self: *Popup, node: *const tree.Node, context: *kwm.Context) void {
        _ = self;

        switch (node.handler) {
            .shell => |cmd| {
                log.info("spawn: {s}", .{cmd});
                _ = context.spawn_shell(cmd);
            },
            .dispatch => |func| {
                log.debug("dispatch function", .{});
                func();
            },
            .none => {},
        }
    }

    pub fn deinit(self: *Popup) void {
        if (self.layer_surface) |*ls| {
            ls.destroy();
        }
        if (self.keyboard) |kb| {
            kb.release();
        }
        if (self.navigator) |*nav| {
            nav.deinit();
        }
        if (self.config) |*cfg| {
            cfg.deinit();
        }
        if (self.settings) |*s| {
            s.deinit();
        }

        global_popup = null;
        self.allocator.destroy(self);
    }
};

/// Simple keycode to ASCII mapping (evdev keycodes)
fn keycodeToAscii(keycode: u32) ?u8 {
    return switch (keycode) {
        // Escape
        1 => 27, // ESC

        // Number row
        2 => '1', 3 => '2', 4 => '3', 5 => '4', 6 => '5',
        7 => '6', 8 => '7', 9 => '8', 10 => '9', 11 => '0',
        12 => '-', 13 => '=',

        // Top row (qwerty)
        16 => 'q', 17 => 'w', 18 => 'e', 19 => 'r', 20 => 't',
        21 => 'y', 22 => 'u', 23 => 'i', 24 => 'o', 25 => 'p',
        26 => '[', 27 => ']',

        // Home row
        30 => 'a', 31 => 's', 32 => 'd', 33 => 'f', 34 => 'g',
        35 => 'h', 36 => 'j', 37 => 'k', 38 => 'l',

        // Bottom row
        44 => 'z', 45 => 'x', 46 => 'c', 47 => 'v', 48 => 'b',
        49 => 'n', 50 => 'm', 51 => ',', 52 => '.',

        // Space, Enter, Tab, Backspace
        28 => '\n', // Enter
        57 => ' ', // Space

        else => null,
    };
}

/// Default menu when no config is found
fn getDefaultMenu(allocator: std.mem.Allocator) ?*const tree.Node {
    const children = allocator.alloc(tree.Node, 3) catch return null;

    // Terminal
    children[0] = .{
        .key = 't',
        .label = "terminal",
        .node_type = .action,
        .behavior = .transient,
        .handler = .{ .shell = "ghostty" },
    };

    // Quit
    children[1] = .{
        .key = 'q',
        .label = "quit",
        .node_type = .action,
        .behavior = .transient,
        .handler = .{ .shell = "pkill basket" },
    };

    // Files
    children[2] = .{
        .key = 'f',
        .label = "files",
        .node_type = .action,
        .behavior = .transient,
        .handler = .{ .shell = "nautilus" },
    };

    const root = allocator.create(tree.Node) catch return null;
    root.* = .{
        .key = ' ',
        .label = "basket",
        .node_type = .submenu,
        .behavior = .transient,
        .children = children,
    };

    return root;
}
