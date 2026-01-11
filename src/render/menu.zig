//! Menu renderer - draws which-key style popup
//!
//! Renders a Node's children as a key → label list
//! Uses fcft for proper font rendering when available.

const std = @import("std");
const bitmap_font = @import("font.zig");
const fcft = @import("fcft_font.zig");
const tree = @import("../tree/navigation.zig");
const settings = @import("../config/settings.zig");

pub const Theme = struct {
    bg: u32 = 0xFF1a1a1a,
    fg: u32 = 0xFFcccccc,
    key_fg: u32 = 0xFFffaa00,
    border: u32 = 0xFF333333,
    title_fg: u32 = 0xFF88aaff,

    padding: u32 = 12,
    line_height: u32 = 16,
    key_width: u32 = 32,

    /// Create Theme from settings
    pub fn fromSettings(s: settings.Theme) Theme {
        return .{
            .bg = s.bg,
            .fg = s.fg,
            .key_fg = s.key,
            .border = s.border,
            .title_fg = s.title,
            .padding = s.padding,
            .line_height = 16 + s.line_spacing, // Will be updated when font loads
            .key_width = 32,
        };
    }
};

pub const MenuRenderer = struct {
    theme: Theme,
    font: ?fcft.Font = null,

    pub fn init(theme: Theme) MenuRenderer {
        return .{ .theme = theme };
    }

    /// Initialize with fcft font
    pub fn initWithFont(theme: Theme, font_family: []const u8, font_size: u32) MenuRenderer {
        var renderer = MenuRenderer{ .theme = theme };

        if (fcft.Font.init(font_family, font_size)) |fnt| {
            renderer.font = fnt;
            // Update theme metrics based on actual font
            renderer.theme.line_height = fnt.height() + 4;
            renderer.theme.key_width = fnt.measureString("w >") + 8;
        } else |_| {
            // Fall back to bitmap font
            renderer.theme.line_height = bitmap_font.GLYPH_HEIGHT + 4;
            renderer.theme.key_width = bitmap_font.GLYPH_WIDTH * 4;
        }

        return renderer;
    }

    pub fn deinit(self: *MenuRenderer) void {
        if (self.font) |*f| {
            f.deinit();
        }
    }

    /// Calculate required dimensions for a menu
    pub fn measure(self: *const MenuRenderer, node: *const tree.Node) struct { w: u32, h: u32 } {
        const children = node.children orelse return .{ .w = 0, .h = 0 };
        const num_items = children.len;

        // Find max label length
        var max_width: u32 = self.measureText(node.label);
        for (children) |child| {
            const w = self.measureText(child.label);
            if (w > max_width) max_width = w;
        }

        const content_width = self.theme.key_width + max_width;
        const width = content_width + self.theme.padding * 2;
        const height = (1 + @as(u32, @intCast(num_items))) * self.theme.line_height + self.theme.padding * 2;

        return .{ .w = width, .h = height };
    }

    fn measureText(self: *const MenuRenderer, text: []const u8) u32 {
        if (self.font) |f| {
            return f.measureString(text);
        } else {
            return @as(u32, @intCast(text.len)) * bitmap_font.GLYPH_WIDTH;
        }
    }

    /// Render menu to pixel buffer
    pub fn render(
        self: *MenuRenderer,
        pixels: []u32,
        pitch: u32,
        width: u32,
        height: u32,
        node: *const tree.Node,
    ) void {
        // Fill background
        @memset(pixels, self.theme.bg);

        // Draw border (1px)
        self.drawBorder(pixels, pitch, width, height);

        const children = node.children orelse return;

        // Draw title
        var y = self.theme.padding;
        self.drawText(pixels, pitch, self.theme.padding, y, node.label, self.theme.title_fg);
        y += self.theme.line_height;

        // Draw separator line
        self.drawHLine(pixels, pitch, self.theme.padding, y - 2, width - self.theme.padding * 2, self.theme.border);

        // Draw each item
        for (children) |child| {
            self.renderItem(pixels, pitch, self.theme.padding, y, &child);
            y += self.theme.line_height;
        }
    }

    fn renderItem(
        self: *MenuRenderer,
        pixels: []u32,
        pitch: u32,
        x: u32,
        y: u32,
        node: *const tree.Node,
    ) void {
        // Draw key
        var key_buf: [1]u8 = .{node.key};
        self.drawText(pixels, pitch, x, y, &key_buf, self.theme.key_fg);

        // Draw arrow or nothing based on type
        const arrow: []const u8 = if (node.node_type == .submenu) " >" else "  ";
        if (self.font) |_| {
            self.drawText(pixels, pitch, x + self.charWidth(), y, arrow, self.theme.fg);
        } else {
            self.drawText(pixels, pitch, x + bitmap_font.GLYPH_WIDTH, y, arrow, self.theme.fg);
        }

        // Draw label
        self.drawText(pixels, pitch, x + self.theme.key_width, y, node.label, self.theme.fg);
    }

    fn charWidth(self: *const MenuRenderer) u32 {
        if (self.font) |f| {
            var font_copy = f;
            return font_copy.measureString("W");
        }
        return bitmap_font.GLYPH_WIDTH;
    }

    fn drawText(
        self: *MenuRenderer,
        pixels: []u32,
        pitch: u32,
        x: u32,
        y: u32,
        text: []const u8,
        color: u32,
    ) void {
        if (self.font) |*f| {
            _ = f.renderString(pixels, pitch, @intCast(x), @intCast(y), text, color);
        } else {
            bitmap_font.renderString(pixels, pitch, x, y, text, color, null);
        }
    }

    fn drawBorder(self: *const MenuRenderer, pixels: []u32, pitch: u32, width: u32, height: u32) void {
        // Top
        self.drawHLine(pixels, pitch, 0, 0, width, self.theme.border);
        // Bottom
        self.drawHLine(pixels, pitch, 0, height - 1, width, self.theme.border);
        // Left
        self.drawVLine(pixels, pitch, 0, 0, height, self.theme.border);
        // Right
        self.drawVLine(pixels, pitch, width - 1, 0, height, self.theme.border);
    }

    fn drawHLine(_: *const MenuRenderer, pixels: []u32, pitch: u32, x: u32, y: u32, len: u32, color: u32) void {
        const start = y * pitch + x;
        const end = @min(start + len, pixels.len);
        if (start < pixels.len) {
            @memset(pixels[start..end], color);
        }
    }

    fn drawVLine(_: *const MenuRenderer, pixels: []u32, pitch: u32, x: u32, y: u32, len: u32, color: u32) void {
        var i: u32 = 0;
        while (i < len) : (i += 1) {
            const idx = (y + i) * pitch + x;
            if (idx < pixels.len) {
                pixels[idx] = color;
            }
        }
    }
};

test "measure menu" {
    const renderer = MenuRenderer.init(.{});
    // Would need a test node here
    _ = renderer;
}
