const std = @import("std");
const mem = std.mem;
const posix = std.posix;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const wp = wayland.client.wp;
const river = wayland.client.river;
const zwlr = wayland.client.zwlr;

const utils = @import("utils");
const kwm = @import("kwm");
const popup_mod = @import("popup.zig");
const theme = @import("theme");

const Globals = struct {
    wl_compositor: ?*wl.Compositor = null,
    wl_shm: ?*wl.Shm = null,
    wl_seat: ?*wl.Seat = null,
    wp_viewporter: ?*wp.Viewporter = null,
    wp_single_pixel_buffer_manager: ?*wp.SinglePixelBufferManagerV1 = null,
    zwlr_layer_shell: ?*zwlr.LayerShellV1 = null,
    rwm: ?*river.WindowManagerV1 = null,
    rwm_xkb_bindings: ?*river.XkbBindingsV1 = null,
    rwm_layer_shell: ?*river.LayerShellV1 = null,
    rwm_input_manager: ?*river.InputManagerV1 = null,
    rwm_libinput_config: ?*river.LibinputConfigV1 = null,
};


pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
    defer if (gpa.deinit() != .ok) @panic("memory leak");
    utils.init_allocator(&gpa.allocator());

    // Load theme before kwm init so values are applied
    const config_dir = theme.getConfigDir(utils.allocator) catch "/etc/basket";
    defer if (!std.mem.eql(u8, config_dir, "/etc/basket")) utils.allocator.free(config_dir);
    theme.load(utils.allocator, config_dir) catch |err| {
        std.debug.print("[theme] load failed: {}, using defaults\n", .{err});
    };
    theme.apply();

    const display = try wl.Display.connect(null);
    defer display.disconnect();

    {
        const registry = display.getRegistry() catch return error.GetRegistryFailed;

        var globals: Globals = .{};
        registry.setListener(*Globals, registry_listener, &globals);

        if (display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

        const wl_compositor = globals.wl_compositor orelse return error.MissingCompositor;
        const wp_single_pixel_buffer_manager = globals.wp_single_pixel_buffer_manager orelse return error.MissingSinglePixelBufferManagerV1;
        const wp_viewporter = globals.wp_viewporter orelse return error.MissingViewporter;
        const rwm = globals.rwm orelse return error.MissingRiverWindowManagerV1;
        const rwm_xkb_bindings = globals.rwm_xkb_bindings orelse return error.MissingRiverXkbBindingsV1;
        const rwm_layer_shell = globals.rwm_layer_shell orelse return error.MissingRiverLayerShellV1;
        const rwm_input_manager = globals.rwm_input_manager orelse return error.MissingRiverInputManager;
        const rwm_libinput_config = globals.rwm_libinput_config orelse return error.MissingRiverLibinputConfig;

        kwm.Context.init(
            registry,
            wl_compositor,
            wp_viewporter,
            wp_single_pixel_buffer_manager,
            rwm,
            rwm_xkb_bindings,
            rwm_layer_shell,
            rwm_input_manager,
            rwm_libinput_config,
        );

        // Initialize popup if layer shell is available
        if (globals.zwlr_layer_shell) |layer_shell| {
            if (globals.wl_shm) |shm| {
                const popup = popup_mod.Popup.init(
                    utils.allocator,
                    wl_compositor,
                    layer_shell,
                    shm,
                ) catch |err| {
                    std.debug.print("[main] popup init failed: {}\n", .{err});
                    return;
                };

                // Pass the seat to popup for keyboard handling
                if (globals.wl_seat) |seat| {
                    popup.setSeat(seat);
                }

                // Load popup menu config (reuse theme config_dir)
                popup.loadConfig(config_dir);

                // Register popup callback with kwm
                kwm.Seat.show_popup_callback = &showPopupWrapper;
            }
        }
    }
    defer kwm.Context.deinit();
    defer if (popup_mod.Popup.get()) |popup| popup.deinit();

    const wayland_fd = display.getFd();
    var poll_fds = [_]posix.pollfd {
        .{ .fd = wayland_fd, .events = posix.POLL.IN, .revents = 0 },
    };

    const context = kwm.Context.get();
    while (context.running) {
        _ = display.flush();
        _ = try posix.poll(&poll_fds, -1);

        if (poll_fds[0].revents & posix.POLL.IN != 0) {
            if (display.dispatch() != .SUCCESS) {
                return error.DispatchFailed;
            }
        }
    }
}


fn showPopupWrapper() void {
    if (popup_mod.Popup.get()) |popup| {
        popup.show() catch |err| {
            std.debug.print("[popup] show failed: {}\n", .{err});
        };
    }
}

fn registry_listener(registry: *wl.Registry, event: wl.Registry.Event, globals: *Globals) void {
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                globals.wl_compositor = registry.bind(global.name, wl.Compositor, 4) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                globals.wl_shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                globals.wl_seat = registry.bind(global.name, wl.Seat, 7) catch return;
            } else if (mem.orderZ(u8, global.interface, wp.Viewporter.interface.name) == .eq) {
                globals.wp_viewporter = registry.bind(global.name, wp.Viewporter, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wp.SinglePixelBufferManagerV1.interface.name) == .eq) {
                globals.wp_single_pixel_buffer_manager = registry.bind(global.name, wp.SinglePixelBufferManagerV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, zwlr.LayerShellV1.interface.name) == .eq) {
                globals.zwlr_layer_shell = registry.bind(global.name, zwlr.LayerShellV1, 4) catch return;
            } else if (mem.orderZ(u8, global.interface, river.WindowManagerV1.interface.name) == .eq) {
                globals.rwm = registry.bind(global.name, river.WindowManagerV1, 2) catch return;
            } else if (mem.orderZ(u8, global.interface, river.XkbBindingsV1.interface.name) == .eq) {
                globals.rwm_xkb_bindings = registry.bind(global.name, river.XkbBindingsV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, river.LayerShellV1.interface.name) == .eq) {
                globals.rwm_layer_shell = registry.bind(global.name, river.LayerShellV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, river.InputManagerV1.interface.name) == .eq) {
                globals.rwm_input_manager = registry.bind(global.name, river.InputManagerV1, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, river.LibinputConfigV1.interface.name) == .eq) {
                globals.rwm_libinput_config = registry.bind(global.name, river.LibinputConfigV1, 1) catch return;
            }
        },
        .global_remove => {},
    }
}
