//! Weaver popup menu
//!
//! Integrates deltas-style which-key popup with kwm's window management.
//! Triggered by leader key, dispatches actions to kwm internals.

const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const kwm = @import("kwm");
const render = @import("render/mod.zig");
const surface = @import("surface/layer.zig");
const tree = @import("tree/navigation.zig");
const zon_config = @import("config/loader.zig");

pub const Popup = struct {
    allocator: std.mem.Allocator,

    // Wayland objects
    compositor: *wl.Compositor,
    layer_shell: *zwlr.LayerShellV1,
    shm: *wl.Shm,

    // Menu state
    layer_surface: ?surface.LayerSurface = null,
    navigator: ?tree.Navigator = null,
    menu_root: ?*const tree.Node = null,
    config: ?zon_config.Config = null,

    // Visibility
    visible: bool = false,

    pub fn init(
        allocator: std.mem.Allocator,
        compositor: *wl.Compositor,
        layer_shell: *zwlr.LayerShellV1,
        shm: *wl.Shm,
    ) Popup {
        return .{
            .allocator = allocator,
            .compositor = compositor,
            .layer_shell = layer_shell,
            .shm = shm,
        };
    }

    pub fn loadConfig(self: *Popup, config_dir: []const u8) !void {
        // Load .zon config
        if (zon_config.load(self.allocator, config_dir)) |cfg| {
            self.config = cfg;
            if (cfg.root) |root| {
                self.menu_root = root;
            }
        } else |_| {
            // Use built-in fallback if no config
        }
    }

    pub fn show(self: *Popup) !void {
        if (self.visible) return;

        if (self.layer_surface == null) {
            // Create layer surface on first show
            const theme = render.Theme{}; // TODO: load from config
            self.layer_surface = surface.LayerSurface.init(
                self.compositor,
                self.layer_shell,
                self.shm,
            );
            try self.layer_surface.?.create();
        }

        if (self.menu_root) |root| {
            if (self.navigator == null) {
                self.navigator = tree.Navigator.init(self.allocator, root);
            }
            self.layer_surface.?.showMenu(root);
        }

        self.visible = true;
    }

    pub fn hide(self: *Popup) void {
        if (!self.visible) return;

        if (self.layer_surface) |*ls| {
            ls.destroy();
            self.layer_surface = null;
        }

        self.visible = false;
    }

    pub fn handleKey(self: *Popup, key: u8) ?Action {
        if (!self.visible) return null;

        if (self.navigator) |*nav| {
            if (nav.handleKey(key)) |nav_action| {
                return self.translateAction(nav_action);
            }
        }

        return null;
    }

    /// Translate tree.NavAction to kwm binding.Action
    fn translateAction(self: *Popup, nav_action: tree.NavAction) ?Action {
        _ = self;

        switch (nav_action) {
            .execute, .execute_and_close => |node| {
                // Parse the shell command to determine kwm action
                // For now, return the raw command
                return Action{ .shell = node.handler };
            },
            .show_menu => |node| {
                if (self.layer_surface) |*ls| {
                    ls.showMenu(node);
                }
                return null;
            },
            .close => {
                return Action.close;
            },
        }
    }

    pub fn deinit(self: *Popup) void {
        if (self.layer_surface) |*ls| {
            ls.destroy();
        }
        if (self.navigator) |*nav| {
            nav.deinit();
        }
        if (self.config) |*cfg| {
            cfg.deinit();
        }
    }
};

/// Actions that can be dispatched to kwm
pub const Action = union(enum) {
    /// Execute shell command
    shell: tree.ActionHandler,

    /// Close popup
    close,

    /// Direct kwm actions (will be expanded)
    focus_left,
    focus_right,
    focus_up,
    focus_down,
    close_window,
    toggle_float,
    set_tag: u32,
};
