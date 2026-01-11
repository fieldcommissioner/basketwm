//! fcft font rendering wrapper
//!
//! Provides fontconfig-based font loading and glyph rendering.

const std = @import("std");
const c = @cImport({
    @cInclude("fcft/fcft.h");
    @cInclude("pixman.h");
});

pub const Font = struct {
    font: *c.fcft_font,

    pub fn init(font_name: []const u8, size: u32) !Font {
        // Build font pattern string: "Family:size=N"
        var buf: [256]u8 = undefined;
        const pattern = std.fmt.bufPrintZ(&buf, "{s}:size={d}", .{ font_name, size }) catch return error.PatternTooLong;

        var names = [_][*c]const u8{pattern.ptr};
        const font = c.fcft_from_name(1, @ptrCast(&names), null) orelse return error.FontNotFound;

        return .{ .font = font };
    }

    pub fn deinit(self: *Font) void {
        c.fcft_destroy(self.font);
    }

    /// Get font metrics
    pub fn height(self: *const Font) u32 {
        return @intCast(self.font.*.height);
    }

    pub fn ascent(self: *const Font) u32 {
        return @intCast(self.font.*.ascent);
    }

    pub fn descent(self: *const Font) u32 {
        return @intCast(self.font.*.descent);
    }

    /// Render a single character, returns glyph width
    pub fn renderChar(
        self: *Font,
        pixels: []u32,
        pitch: u32,
        x: i32,
        y: i32,
        char: u21,
        fg_color: u32,
    ) u32 {
        const glyph = c.fcft_rasterize_char_utf32(self.font, char, c.FCFT_SUBPIXEL_NONE) orelse return 0;

        // Render glyph to pixel buffer
        const glyph_x = x + glyph.*.x;
        const glyph_y = y + @as(i32, @intCast(self.font.*.ascent)) - glyph.*.y;

        self.blitGlyph(pixels, pitch, glyph_x, glyph_y, glyph, fg_color);

        return @intCast(glyph.*.advance.x);
    }

    /// Render a string, returns total width
    pub fn renderString(
        self: *Font,
        pixels: []u32,
        pitch: u32,
        x: i32,
        y: i32,
        text: []const u8,
        fg_color: u32,
    ) u32 {
        var cx = x;
        var i: usize = 0;
        while (i < text.len) {
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            const codepoint = std.unicode.utf8Decode(text[i..][0..len]) catch '?';
            const advance = self.renderChar(pixels, pitch, cx, y, codepoint, fg_color);
            cx += @intCast(advance);
            i += len;
        }
        return @intCast(cx - x);
    }

    fn blitGlyph(
        self: *Font,
        pixels: []u32,
        pitch: u32,
        gx: i32,
        gy: i32,
        glyph: *const c.fcft_glyph,
        fg_color: u32,
    ) void {
        _ = self;

        const pix = glyph.*.pix orelse return;
        const glyph_data_raw = c.pixman_image_get_data(pix);
        if (glyph_data_raw == null) return;

        // a8 format: stride is in bytes, each pixel is 1 byte (alpha only)
        const glyph_stride = @as(u32, @intCast(c.pixman_image_get_stride(pix)));
        const glyph_width = @as(u32, @intCast(c.pixman_image_get_width(pix)));
        const glyph_height = @as(u32, @intCast(c.pixman_image_get_height(pix)));

        // Cast to byte pointer for a8 format
        const glyph_data: [*]const u8 = @ptrCast(glyph_data_raw);

        // Extract fg color components
        const fg_r = (fg_color >> 16) & 0xFF;
        const fg_g = (fg_color >> 8) & 0xFF;
        const fg_b = fg_color & 0xFF;

        var row: u32 = 0;
        while (row < glyph_height) : (row += 1) {
            const py = gy + @as(i32, @intCast(row));
            if (py < 0) continue;

            var col: u32 = 0;
            while (col < glyph_width) : (col += 1) {
                const px = gx + @as(i32, @intCast(col));
                if (px < 0) continue;

                const dst_idx = @as(u32, @intCast(py)) * pitch + @as(u32, @intCast(px));
                if (dst_idx >= pixels.len) continue;

                // a8 format: each byte is the alpha value directly
                const src_idx = row * glyph_stride + col;
                const alpha = glyph_data[src_idx];

                if (alpha == 0) continue;

                if (alpha == 255) {
                    pixels[dst_idx] = fg_color;
                } else {
                    // Alpha blend
                    const dst = pixels[dst_idx];
                    const dst_r = (dst >> 16) & 0xFF;
                    const dst_g = (dst >> 8) & 0xFF;
                    const dst_b = dst & 0xFF;

                    const inv_alpha = 255 - alpha;
                    const r = (fg_r * alpha + dst_r * inv_alpha) / 255;
                    const g = (fg_g * alpha + dst_g * inv_alpha) / 255;
                    const b = (fg_b * alpha + dst_b * inv_alpha) / 255;

                    pixels[dst_idx] = 0xFF000000 | (r << 16) | (g << 8) | b;
                }
            }
        }
    }

    /// Measure string width without rendering
    pub fn measureString(self: *const Font, text: []const u8) u32 {
        var width: u32 = 0;
        var i: usize = 0;
        while (i < text.len) {
            const len = std.unicode.utf8ByteSequenceLength(text[i]) catch 1;
            const codepoint = std.unicode.utf8Decode(text[i..][0..len]) catch '?';

            const glyph = c.fcft_rasterize_char_utf32(self.font, codepoint, c.FCFT_SUBPIXEL_NONE);
            if (glyph) |g| {
                width += @intCast(g.*.advance.x);
            }
            i += len;
        }
        return width;
    }
};

/// Initialize fcft library (call once at startup)
pub fn init() void {
    _ = c.fcft_init(c.FCFT_LOG_COLORIZE_AUTO, false, c.FCFT_LOG_CLASS_WARNING);
}

/// Cleanup fcft library
pub fn deinit() void {
    c.fcft_fini();
}

test "fcft init" {
    init();
    defer deinit();

    var font = try Font.init("monospace", 14);
    defer font.deinit();

    try std.testing.expect(font.height() > 0);
}
