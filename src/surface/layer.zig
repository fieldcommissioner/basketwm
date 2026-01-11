//! Layer-shell surface for Deltas popup
//!
//! Creates an overlay surface that:
//!   - Floats above all windows (overlay layer)
//!   - Grabs keyboard focus
//!   - Can be positioned and sized

const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const render = @import("../render/mod.zig");
const tree = @import("../tree/navigation.zig");

pub const LayerSurface = struct {
    compositor: *wl.Compositor,
    layer_shell: *zwlr.LayerShellV1,
    shm: *wl.Shm,
    surface: ?*wl.Surface = null,
    layer_surface: ?*zwlr.LayerSurfaceV1 = null,
    buffer: ?render.ShmBuffer = null,
    menu_renderer: render.MenuRenderer,

    // Current menu node to display
    current_node: ?*const tree.Node = null,

    // Surface dimensions
    width: u32 = 400,
    height: u32 = 300,

    // State
    configured: bool = false,
    closed: bool = false,

    pub fn init(compositor: *wl.Compositor, layer_shell: *zwlr.LayerShellV1, shm: *wl.Shm) LayerSurface {
        return .{
            .compositor = compositor,
            .layer_shell = layer_shell,
            .shm = shm,
            .menu_renderer = render.MenuRenderer.init(.{}),
        };
    }

    pub fn initWithTheme(compositor: *wl.Compositor, layer_shell: *zwlr.LayerShellV1, shm: *wl.Shm, theme: render.Theme) LayerSurface {
        return .{
            .compositor = compositor,
            .layer_shell = layer_shell,
            .shm = shm,
            .menu_renderer = render.MenuRenderer.init(theme),
        };
    }

    pub fn initWithFont(compositor: *wl.Compositor, layer_shell: *zwlr.LayerShellV1, shm: *wl.Shm, theme: render.Theme, font_family: []const u8, font_size: u32) LayerSurface {
        return .{
            .compositor = compositor,
            .layer_shell = layer_shell,
            .shm = shm,
            .menu_renderer = render.MenuRenderer.initWithFont(theme, font_family, font_size),
        };
    }

    pub fn create(self: *LayerSurface) !void {
        // Create wl_surface
        self.surface = self.compositor.createSurface() catch return error.CreateSurfaceFailed;

        // Create layer surface on overlay layer (topmost)
        self.layer_surface = self.layer_shell.getLayerSurface(
            self.surface.?,
            null, // output - null means compositor chooses
            .overlay, // layer - overlay is topmost
            "deltas", // namespace
        ) catch return error.CreateLayerSurfaceFailed;

        // Configure the layer surface
        const ls = self.layer_surface.?;

        // Request keyboard interactivity
        ls.setKeyboardInteractivity(.exclusive);

        // Set size (0 means use anchor-based sizing)
        ls.setSize(self.width, self.height);

        // Anchor to bottom-right corner
        ls.setAnchor(.{ .bottom = true, .right = true });

        // Add margin from edge
        ls.setMargin(0, 20, 20, 0); // top, right, bottom, left

        // Set up listener for configure events
        ls.setListener(*LayerSurface, layerSurfaceListener, self);

        // Commit to trigger configure
        self.surface.?.commit();
    }

    pub fn destroy(self: *LayerSurface) void {
        if (self.buffer) |*buf| {
            buf.destroy();
        }
        if (self.layer_surface) |ls| {
            ls.destroy();
        }
        if (self.surface) |s| {
            s.destroy();
        }
    }

    fn layerSurfaceListener(
        layer_surface: *zwlr.LayerSurfaceV1,
        event: zwlr.LayerSurfaceV1.Event,
        self: *LayerSurface,
    ) void {
        switch (event) {
            .configure => |configure| {
                std.debug.print("[layer] configure: {}x{}\n", .{ configure.width, configure.height });

                // Use suggested size if provided
                if (configure.width > 0) self.width = configure.width;
                if (configure.height > 0) self.height = configure.height;

                // Acknowledge the configure
                layer_surface.ackConfigure(configure.serial);

                // Mark as configured
                self.configured = true;

                // Create and attach buffer
                self.attachBuffer() catch |err| {
                    std.debug.print("[layer] buffer attach failed: {}\n", .{err});
                };
            },
            .closed => {
                std.debug.print("[layer] closed by compositor\n", .{});
                self.closed = true;
            },
        }
    }

    fn attachBuffer(self: *LayerSurface) !void {
        // Create buffer if we don't have one (or size changed)
        if (self.buffer == null) {
            self.buffer = render.ShmBuffer.init(self.shm, self.width, self.height);
            try self.buffer.?.create();
            std.debug.print("[layer] created {}x{} buffer\n", .{ self.width, self.height });
        }

        // Render content
        if (self.buffer.?.pixels()) |pixels| {
            if (self.current_node) |node| {
                // Render menu
                self.menu_renderer.render(pixels, self.width, self.width, self.height, node);
            } else {
                // Just fill with background
                @memset(pixels, 0xFF1a1a1a);
            }
        }

        // Attach to surface
        if (self.surface) |s| {
            if (self.buffer.?.getBuffer()) |buf| {
                s.attach(buf, 0, 0);
                s.damageBuffer(0, 0, @intCast(self.width), @intCast(self.height));
                s.commit();
                std.debug.print("[layer] buffer attached and committed\n", .{});
            }
        }
    }

    /// Update the displayed menu and redraw
    pub fn showMenu(self: *LayerSurface, node: *const tree.Node) void {
        self.current_node = node;
        if (self.configured) {
            self.redraw();
        }
    }

    /// Redraw the surface with current content
    pub fn redraw(self: *LayerSurface) void {
        if (self.buffer) |*buf| {
            if (buf.pixels()) |pixels| {
                if (self.current_node) |node| {
                    self.menu_renderer.render(pixels, self.width, self.width, self.height, node);
                } else {
                    @memset(pixels, 0xFF1a1a1a);
                }
            }

            // Commit the update
            if (self.surface) |s| {
                if (buf.getBuffer()) |wl_buf| {
                    s.attach(wl_buf, 0, 0);
                    s.damageBuffer(0, 0, @intCast(self.width), @intCast(self.height));
                    s.commit();
                }
            }
        }
    }

    pub fn isReady(self: *const LayerSurface) bool {
        return self.configured and !self.closed;
    }
};
