//! Rendering module

pub const buffer = @import("buffer.zig");
pub const bitmap_font = @import("font.zig");
pub const fcft_font = @import("fcft_font.zig");
pub const menu = @import("menu.zig");
pub const popup = @import("popup.zig");

pub const ShmBuffer = buffer.ShmBuffer;
pub const MenuRenderer = menu.MenuRenderer;
pub const Theme = menu.Theme;
pub const Popup = popup.Popup;
pub const Style = popup.Style;
pub const Font = fcft_font.Font;

// Bitmap font fallback
pub const renderChar = bitmap_font.renderChar;
pub const renderString = bitmap_font.renderString;
pub const GLYPH_WIDTH = bitmap_font.GLYPH_WIDTH;
pub const GLYPH_HEIGHT = bitmap_font.GLYPH_HEIGHT;

// Theme creation from settings
pub const themeFromSettings = Theme.fromSettings;

// fcft initialization
pub const initFcft = fcft_font.init;
pub const deinitFcft = fcft_font.deinit;
