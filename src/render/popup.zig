//! Popup rendering for deltas
//!
//! Renders the which-key menu to a corner of the screen.
//! Uses River shell surfaces for proper compositor integration.

const std = @import("std");
const tree = @import("../tree/navigation.zig");

pub const Style = struct {
    bg_color: u32 = 0x1a1a1aff,     // dark background
    fg_color: u32 = 0xccccccff,     // light text
    highlight_color: u32 = 0x4a9fffff, // selection highlight
    key_color: u32 = 0xffaa00ff,    // key hints

    font_size: u16 = 14,
    padding: u16 = 8,
    line_height: u16 = 20,

    corner_radius: u16 = 4,
    fade_duration_ms: u16 = 100,
};

pub const Popup = struct {
    style: Style,
    visible: bool = false,
    width: u32 = 0,
    height: u32 = 0,
    buffer: ?[]u8 = null,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, style: Style) Popup {
        return Popup{
            .style = style,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Popup) void {
        if (self.buffer) |buf| {
            self.allocator.free(buf);
        }
    }

    pub fn render(self: *Popup, node: *tree.Node) !void {
        // Calculate dimensions based on children
        const children = node.children orelse return;
        const num_items = children.len;

        self.height = @intCast(self.style.padding * 2 + num_items * self.style.line_height);
        self.width = self.calculateWidth(children);

        // TODO: Actually render to buffer
        // - Background rect with corner radius
        // - For each child: "key  label"
        // - Highlight current selection if any

        self.visible = true;
    }

    fn calculateWidth(self: *Popup, children: []tree.Node) u32 {
        var max_len: usize = 0;
        for (children) |child| {
            const len = child.label.len + 4; // "k  label"
            if (len > max_len) max_len = len;
        }
        // Approximate: chars * font_size * 0.6 + padding
        return @intCast(max_len * self.style.font_size * 6 / 10 + self.style.padding * 2);
    }

    pub fn hide(self: *Popup) void {
        self.visible = false;
    }

    pub fn getBuffer(self: *Popup) ?[]const u8 {
        return self.buffer;
    }
};

test "render placeholder" {
    try std.testing.expect(true);
}
