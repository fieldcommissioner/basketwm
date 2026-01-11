const Self = @This();

const std = @import("std");
const mem = std.mem;
const log = std.log.scoped(.input_device);

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const utils = @import("utils");
const config = @import("config");


link: wl.list.Link = undefined,

rwm_input_device: *river.InputDeviceV1,

name: ?[]const u8 = null,
type: river.InputDeviceV1.Type = undefined,


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

    if (self.name) |name| {
        utils.allocator.free(name);
    }

    self.link.remove();
    self.rwm_input_device.destroy();

    utils.allocator.destroy(self);
}


fn set_name(self: *Self, name: []const u8) void {
    if (self.name) |name_| {
        utils.allocator.free(name_);
        self.name = null;
    }
    self.name = utils.allocator.dupe(u8, name) catch null;
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

            input_device.type = data.type;
        },
        .name => |data| {
            log.debug("<{*}> name: {s}", .{ input_device, data.name });

            input_device.set_name(mem.span(data.name));
        },
        .removed => {
            log.debug("<{*}> removed", .{ input_device });

            input_device.destroy();
        }
    }
}
