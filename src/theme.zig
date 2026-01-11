//! Runtime theme configuration for Basket
//!
//! Loads visual settings from ~/.config/basket/theme.zon at startup.
//! Allows ricing without recompilation.

const std = @import("std");
const log = std.log.scoped(.theme);

const utils = @import("utils");

/// Runtime theme settings
pub const Theme = struct {
    // Border settings
    border_width: i32 = 5,
    border_color_focus: u32 = 0xffc777ff,
    border_color_unfocus: u32 = 0x828bb8ff,
    border_color_urgent: u32 = 0xff0000ff,

    // Gap settings
    tile_inner_gap: i32 = 12,
    tile_outer_gap: i32 = 9,
    monocle_gap: i32 = 9,
    scroller_inner_gap: i32 = 16,
    scroller_outer_gap: i32 = 9,

    // Layout defaults
    tile_mfact: f32 = 0.55,
    tile_nmaster: i32 = 1,
    scroller_mfact: f32 = 0.5,

    // UI scaling (applied via environment)
    scale: f32 = 1.0,

    // Output-specific scales (output_name -> scale)
    // Parsed separately due to dynamic nature
};

// Global theme instance
var global_theme: Theme = .{};
var theme_loaded: bool = false;

pub fn get() *Theme {
    return &global_theme;
}

pub fn isLoaded() bool {
    return theme_loaded;
}

/// Load theme from config directory
pub fn load(allocator: std.mem.Allocator, config_dir: []const u8) !void {
    const path = try std.fs.path.join(allocator, &.{ config_dir, "theme.zon" });
    defer allocator.free(path);

    const file = std.fs.cwd().openFile(path, .{}) catch |err| {
        if (err == error.FileNotFound) {
            log.info("no theme.zon found, using defaults", .{});
            theme_loaded = true;
            return;
        }
        return err;
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 64);
    defer allocator.free(content);

    try parseTheme(content);
    theme_loaded = true;
    log.info("loaded theme from {s}", .{path});
}

fn parseTheme(content: []const u8) !void {
    // Simple manual parsing since Zig's @import for zon is compile-time only
    // Look for key = value patterns

    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '/' or trimmed[0] == '.') continue;

        // Parse .key = value,
        if (std.mem.startsWith(u8, trimmed, ".")) {
            if (parseLine(trimmed[1..])) |_| {} else |_| {}
        }
    }
}

fn parseLine(line: []const u8) !void {
    // Find = sign
    const eq_pos = std.mem.indexOf(u8, line, "=") orelse return;
    const key = std.mem.trim(u8, line[0..eq_pos], " \t");

    // Get value (strip trailing comma and whitespace)
    var value = std.mem.trim(u8, line[eq_pos + 1 ..], " \t");
    if (value.len > 0 and value[value.len - 1] == ',') {
        value = value[0 .. value.len - 1];
    }
    value = std.mem.trim(u8, value, " \t");

    // Match known keys
    if (std.mem.eql(u8, key, "border_width")) {
        global_theme.border_width = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "border_color_focus")) {
        global_theme.border_color_focus = try parseColor(value);
    } else if (std.mem.eql(u8, key, "border_color_unfocus")) {
        global_theme.border_color_unfocus = try parseColor(value);
    } else if (std.mem.eql(u8, key, "border_color_urgent")) {
        global_theme.border_color_urgent = try parseColor(value);
    } else if (std.mem.eql(u8, key, "tile_inner_gap")) {
        global_theme.tile_inner_gap = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "tile_outer_gap")) {
        global_theme.tile_outer_gap = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "monocle_gap")) {
        global_theme.monocle_gap = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "scroller_inner_gap")) {
        global_theme.scroller_inner_gap = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "scroller_outer_gap")) {
        global_theme.scroller_outer_gap = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "tile_mfact")) {
        global_theme.tile_mfact = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "tile_nmaster")) {
        global_theme.tile_nmaster = try std.fmt.parseInt(i32, value, 10);
    } else if (std.mem.eql(u8, key, "scroller_mfact")) {
        global_theme.scroller_mfact = try std.fmt.parseFloat(f32, value);
    } else if (std.mem.eql(u8, key, "scale")) {
        global_theme.scale = try std.fmt.parseFloat(f32, value);
    }
}

fn parseColor(value: []const u8) !u32 {
    // Handle 0xRRGGBBAA format
    if (std.mem.startsWith(u8, value, "0x")) {
        return try std.fmt.parseInt(u32, value[2..], 16);
    }
    // Handle #RRGGBB format (add FF alpha)
    if (value.len > 0 and value[0] == '#') {
        const hex = value[1..];
        const rgb = try std.fmt.parseInt(u32, hex, 16);
        return (rgb << 8) | 0xFF;
    }
    return try std.fmt.parseInt(u32, value, 16);
}

/// Apply theme to kwm config vars
pub fn apply() void {
    const config = @import("config");
    const t = get();

    // Apply border settings
    config.border_width = t.border_width;
    // Note: border_color is a var struct, assign via pointer
    const bc_ptr: *@TypeOf(config.border_color) = &config.border_color;
    bc_ptr.focus = t.border_color_focus;
    bc_ptr.unfocus = t.border_color_unfocus;
    bc_ptr.urgent = t.border_color_urgent;

    // Apply layout settings
    config.layout.tile.inner_gap = t.tile_inner_gap;
    config.layout.tile.outer_gap = t.tile_outer_gap;
    config.layout.tile.mfact = t.tile_mfact;
    config.layout.tile.nmaster = t.tile_nmaster;
    config.layout.monocle.gap = t.monocle_gap;
    config.layout.scroller.inner_gap = t.scroller_inner_gap;
    config.layout.scroller.outer_gap = t.scroller_outer_gap;
    config.layout.scroller.mfact = t.scroller_mfact;

    log.info("theme applied: border={}, gaps={}/{}, colors=0x{x}/0x{x}", .{
        t.border_width,
        t.tile_inner_gap,
        t.tile_outer_gap,
        t.border_color_focus,
        t.border_color_unfocus,
    });
}

/// Apply UI scale environment variables
pub fn applyScale(env: *std.process.EnvMap) void {
    const theme = get();
    if (theme.scale == 1.0) return;

    var buf: [16]u8 = undefined;
    const scale_str = std.fmt.bufPrint(&buf, "{d:.2}", .{theme.scale}) catch return;

    env.put("GDK_SCALE", scale_str) catch {};
    env.put("GDK_DPI_SCALE", scale_str) catch {};
    env.put("QT_SCALE_FACTOR", scale_str) catch {};
    env.put("QT_AUTO_SCREEN_SCALE_FACTOR", "0") catch {};

    log.info("scale environment set to {d:.2}", .{theme.scale});
}

/// Get config directory
pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg| {
        return std.fs.path.join(allocator, &.{ xdg, "basket" });
    }
    if (std.posix.getenv("HOME")) |home| {
        return std.fs.path.join(allocator, &.{ home, ".config", "basket" });
    }
    return error.NoHomeDir;
}
