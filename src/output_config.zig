//! Output configuration via wlr-output-management-v1
//!
//! Sets output scale based on theme.zon .scale value.
//! This is the proper Wayland way to do HiDPI scaling.

const std = @import("std");
const log = std.log.scoped(.output_config);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const zwlr = wayland.client.zwlr;

const theme = @import("theme");

var output_manager: ?*zwlr.OutputManagerV1 = null;
var pending_serial: u32 = 0;
var heads: std.ArrayListUnmanaged(*zwlr.OutputHeadV1) = .empty;
var allocator: std.mem.Allocator = undefined;

pub fn init(alloc: std.mem.Allocator, registry: *wl.Registry, name: u32) void {
    allocator = alloc;
    output_manager = registry.bind(name, zwlr.OutputManagerV1, 4) catch |err| {
        log.err("failed to bind output manager: {}", .{err});
        return;
    };

    output_manager.?.setListener(?*anyopaque, outputManagerListener, null);
    log.info("output manager bound", .{});
}

fn outputManagerListener(
    _: *zwlr.OutputManagerV1,
    event: zwlr.OutputManagerV1.Event,
    _: ?*anyopaque,
) void {
    switch (event) {
        .head => |head_event| {
            log.info("new output head: {*}", .{head_event.head});
            heads.append(allocator, head_event.head) catch return;
            head_event.head.setListener(?*anyopaque, headListener, null);
        },
        .done => |done| {
            pending_serial = done.serial;
            log.info("output manager done, serial={}", .{done.serial});

            // Apply scale configuration
            applyScale();
        },
        .finished => {
            log.info("output manager finished", .{});
            output_manager = null;
        },
    }
}

fn headListener(
    head: *zwlr.OutputHeadV1,
    event: zwlr.OutputHeadV1.Event,
    _: ?*anyopaque,
) void {
    switch (event) {
        .name => |name| {
            log.info("head name: {s}", .{name.name});
        },
        .scale => |scale| {
            log.info("head current scale: {d}", .{scale.scale});
        },
        .finished => {
            // Remove from list
            for (heads.items, 0..) |h, i| {
                if (h == head) {
                    _ = heads.swapRemove(i);
                    break;
                }
            }
        },
        else => {},
    }
}

fn applyScale() void {
    const mgr = output_manager orelse return;
    const scale = theme.get().scale;

    if (scale == 1.0) {
        log.info("scale is 1.0, no configuration needed", .{});
        return;
    }

    if (heads.items.len == 0) {
        log.warn("no output heads to configure", .{});
        return;
    }

    log.info("applying scale {d} to {} heads", .{ scale, heads.items.len });

    // Create configuration
    const config = mgr.createConfiguration(pending_serial) catch |err| {
        log.err("failed to create configuration: {}", .{err});
        return;
    };

    config.setListener(?*anyopaque, configListener, null);

    // Enable each head with new scale
    for (heads.items) |head| {
        const head_config = config.enableHead(head) catch |err| {
            log.err("failed to enable head: {}", .{err});
            continue;
        };

        // Set scale (convert f32 to wl_fixed via fromDouble)
        head_config.setScale(wl.Fixed.fromDouble(@floatCast(scale)));
        log.info("set head scale to {d}", .{scale});
    }

    // Apply the configuration
    config.apply();
    log.info("configuration applied", .{});
}

fn configListener(
    config: *zwlr.OutputConfigurationV1,
    event: zwlr.OutputConfigurationV1.Event,
    _: ?*anyopaque,
) void {
    switch (event) {
        .succeeded => {
            log.info("output configuration succeeded!", .{});
            config.destroy();
        },
        .failed => {
            log.err("output configuration failed", .{});
            config.destroy();
        },
        .cancelled => {
            log.warn("output configuration cancelled", .{});
            config.destroy();
        },
    }
}

pub fn isAvailable() bool {
    return output_manager != null;
}
