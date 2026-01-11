const layout = @import("layout.zig");

pub const Direction = enum {
    forward,
    reverse,
};

pub const State = struct {
    layout: ?layout.Type,
};
