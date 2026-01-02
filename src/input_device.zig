const Self = @This();

const std = @import("std");
const log = std.log.scoped(.input_device);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const utils = @import("utils.zig");
const config = @import("config.zig");

link: wl.list.Link = undefined,

rwm_input_device: *river.InputDeviceV1,


pub fn create(rwm_input_device: *river.InputDeviceV1) !*Self {
    const input_device = try utils.allocator.create(Self);
    errdefer utils.allocator.destroy(input_device);

    log.debug("<{*}> created", .{ input_device });

    input_device.* = .{
        .rwm_input_device = rwm_input_device,
    };
    input_device.link.init();

    rwm_input_device.setListener(*Self, rwm_input_device_listener, input_device);

    return input_device;
}


pub fn destroy(self: *Self) void {
    log.debug("<{*}> destroied", .{ self });

    self.link.remove();
    self.rwm_input_device.destroy();

    utils.allocator.destroy(self);
}


fn rwm_input_device_listener(rwm_input_device: *river.InputDeviceV1, event: river.InputDeviceV1.Event, input_device: *Self) void {
    std.debug.assert(rwm_input_device == input_device.rwm_input_device);

    switch (event) {
        .type => |data| {
            log.debug("<{*}> type: {s}", .{ input_device, @tagName(data.type) });

            switch (data.type) {
                .keyboard => {
                    log.debug("<{*}> set repeat info: (rate: {}, delay: {})", .{ input_device, config.repeat_rate, config.repeat_delay});

                    rwm_input_device.setRepeatInfo(config.repeat_rate, config.repeat_delay);
                },
                .pointer => {
                    log.debug("<{*}> set scroll factor: {}", .{ input_device, config.scroll_factor });
                    rwm_input_device.setScrollFactor(.fromDouble(config.scroll_factor));
                },
                else => {}
            }
        },
        .name => |data| {
            log.debug("<{*}> name: {s}", .{ input_device, data.name });
        },
        .removed => {
            log.debug("<{*}> removed", .{ input_device });

            input_device.destroy();
        }
    }
}
