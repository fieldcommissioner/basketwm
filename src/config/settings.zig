//! Global settings from config.zon
//!
//! Handles theme, font, behavior configuration.

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Settings = struct {
    // Trigger
    leader_key: []const u8 = "super",
    timeout_ms: u32 = 300,
    position: Position = .bottom_right,

    // Theme
    theme: Theme = .{},

    // Font
    font: Font = .{},

    // Behavior
    close_on_execute: bool = true,
    show_hints: bool = true,
    animate: bool = true,
    fade_ms: u32 = 100,

    allocator: Allocator,

    pub fn deinit(self: *Settings) void {
        self.allocator.free(self.leader_key);
        self.allocator.free(self.font.family);
    }
};

pub const Position = enum {
    top_left,
    top_center,
    top_right,
    center,
    bottom_left,
    bottom_center,
    bottom_right,
};

pub const Theme = struct {
    // Colors (ARGB)
    bg: u32 = 0xFF1a1a1a,
    fg: u32 = 0xFFcccccc,
    key: u32 = 0xFFffaa00,
    border: u32 = 0xFF333333,
    title: u32 = 0xFF88aaff,
    highlight: u32 = 0xFF3a3a3a,

    // Sizing
    padding: u32 = 12,
    border_width: u32 = 1,
    corner_radius: u32 = 4,
    line_spacing: u32 = 4,
};

pub const Font = struct {
    family: []const u8 = "monospace",
    size: u32 = 14,
    bold: bool = false,
};

// Built-in theme presets
pub const presets = struct {
    pub const default = Theme{};

    pub const gruvbox = Theme{
        .bg = 0xFF282828,
        .fg = 0xFFebdbb2,
        .key = 0xFFfe8019,
        .border = 0xFF3c3836,
        .title = 0xFF83a598,
        .highlight = 0xFF3c3836,
    };

    pub const catppuccin = Theme{
        .bg = 0xFF1e1e2e,
        .fg = 0xFFcdd6f4,
        .key = 0xFFf9e2af,
        .border = 0xFF313244,
        .title = 0xFF89b4fa,
        .highlight = 0xFF313244,
    };

    pub const nord = Theme{
        .bg = 0xFF2e3440,
        .fg = 0xFFeceff4,
        .key = 0xFFebcb8b,
        .border = 0xFF3b4252,
        .title = 0xFF88c0d0,
        .highlight = 0xFF3b4252,
    };

    pub const dracula = Theme{
        .bg = 0xFF282a36,
        .fg = 0xFFf8f8f2,
        .key = 0xFFf1fa8c,
        .border = 0xFF44475a,
        .title = 0xFF8be9fd,
        .highlight = 0xFF44475a,
    };

    pub const tokyo_night = Theme{
        .bg = 0xFF1a1b26,
        .fg = 0xFFc0caf5,
        .key = 0xFFe0af68,
        .border = 0xFF24283b,
        .title = 0xFF7aa2f7,
        .highlight = 0xFF24283b,
    };
};

pub const Parser = struct {
    allocator: Allocator,
    source: []const u8,
    pos: usize = 0,

    const Error = error{
        UnexpectedToken,
        InvalidSyntax,
        UnexpectedEof,
        OutOfMemory,
        InvalidUtf8,
    } || Allocator.Error;

    pub fn init(allocator: Allocator, source: []const u8) Parser {
        return .{
            .allocator = allocator,
            .source = source,
        };
    }

    pub fn parse(self: *Parser) Error!Settings {
        var settings = Settings{
            .allocator = self.allocator,
            .leader_key = try self.allocator.dupe(u8, "super"),
            .font = .{ .family = try self.allocator.dupe(u8, "monospace") },
        };

        self.skipWhitespaceAndComments();
        try self.expect('.');
        try self.expect('{');

        while (true) {
            self.skipWhitespaceAndComments();
            if (self.peek() == '}') {
                self.pos += 1;
                break;
            }

            try self.expect('.');
            const field = try self.parseIdentifier();

            self.skipWhitespaceAndComments();
            try self.expect('=');
            self.skipWhitespaceAndComments();

            if (std.mem.eql(u8, field, "leader_key")) {
                self.allocator.free(settings.leader_key);
                settings.leader_key = try self.parseString();
            } else if (std.mem.eql(u8, field, "timeout_ms")) {
                settings.timeout_ms = try self.parseNumber();
            } else if (std.mem.eql(u8, field, "position")) {
                settings.position = try self.parsePosition();
            } else if (std.mem.eql(u8, field, "theme")) {
                settings.theme = try self.parseTheme();
            } else if (std.mem.eql(u8, field, "font")) {
                self.allocator.free(settings.font.family);
                settings.font = try self.parseFont();
            } else if (std.mem.eql(u8, field, "close_on_execute")) {
                settings.close_on_execute = try self.parseBool();
            } else if (std.mem.eql(u8, field, "show_hints")) {
                settings.show_hints = try self.parseBool();
            } else if (std.mem.eql(u8, field, "animate")) {
                settings.animate = try self.parseBool();
            } else if (std.mem.eql(u8, field, "fade_ms")) {
                settings.fade_ms = try self.parseNumber();
            }

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') self.pos += 1;
        }

        return settings;
    }

    fn parseTheme(self: *Parser) Error!Theme {
        if (self.peek() == '.') {
            // Named preset
            self.pos += 1;
            const name = try self.parseIdentifier();
            if (std.mem.eql(u8, name, "gruvbox")) return presets.gruvbox;
            if (std.mem.eql(u8, name, "catppuccin")) return presets.catppuccin;
            if (std.mem.eql(u8, name, "nord")) return presets.nord;
            if (std.mem.eql(u8, name, "dracula")) return presets.dracula;
            if (std.mem.eql(u8, name, "tokyo_night")) return presets.tokyo_night;
            return presets.default;
        }

        // Inline theme
        var theme = Theme{};
        try self.expect('.');
        try self.expect('{');

        while (true) {
            self.skipWhitespaceAndComments();
            if (self.peek() == '}') {
                self.pos += 1;
                break;
            }

            try self.expect('.');
            const field = try self.parseIdentifier();

            self.skipWhitespaceAndComments();
            try self.expect('=');
            self.skipWhitespaceAndComments();

            if (std.mem.eql(u8, field, "bg")) {
                theme.bg = try self.parseHexColor();
            } else if (std.mem.eql(u8, field, "fg")) {
                theme.fg = try self.parseHexColor();
            } else if (std.mem.eql(u8, field, "key")) {
                theme.key = try self.parseHexColor();
            } else if (std.mem.eql(u8, field, "border")) {
                theme.border = try self.parseHexColor();
            } else if (std.mem.eql(u8, field, "title")) {
                theme.title = try self.parseHexColor();
            } else if (std.mem.eql(u8, field, "highlight")) {
                theme.highlight = try self.parseHexColor();
            } else if (std.mem.eql(u8, field, "padding")) {
                theme.padding = try self.parseNumber();
            } else if (std.mem.eql(u8, field, "border_width")) {
                theme.border_width = try self.parseNumber();
            } else if (std.mem.eql(u8, field, "corner_radius")) {
                theme.corner_radius = try self.parseNumber();
            } else if (std.mem.eql(u8, field, "line_spacing")) {
                theme.line_spacing = try self.parseNumber();
            }

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') self.pos += 1;
        }

        return theme;
    }

    fn parseFont(self: *Parser) Error!Font {
        var font = Font{
            .family = try self.allocator.dupe(u8, "monospace"),
        };

        try self.expect('.');
        try self.expect('{');

        while (true) {
            self.skipWhitespaceAndComments();
            if (self.peek() == '}') {
                self.pos += 1;
                break;
            }

            try self.expect('.');
            const field = try self.parseIdentifier();

            self.skipWhitespaceAndComments();
            try self.expect('=');
            self.skipWhitespaceAndComments();

            if (std.mem.eql(u8, field, "family")) {
                self.allocator.free(font.family);
                font.family = try self.parseString();
            } else if (std.mem.eql(u8, field, "size")) {
                font.size = try self.parseNumber();
            } else if (std.mem.eql(u8, field, "bold")) {
                font.bold = try self.parseBool();
            }

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') self.pos += 1;
        }

        return font;
    }

    fn parsePosition(self: *Parser) Error!Position {
        try self.expect('.');
        const name = try self.parseIdentifier();
        if (std.mem.eql(u8, name, "top_left")) return .top_left;
        if (std.mem.eql(u8, name, "top_center")) return .top_center;
        if (std.mem.eql(u8, name, "top_right")) return .top_right;
        if (std.mem.eql(u8, name, "center")) return .center;
        if (std.mem.eql(u8, name, "bottom_left")) return .bottom_left;
        if (std.mem.eql(u8, name, "bottom_center")) return .bottom_center;
        return .bottom_right;
    }

    fn parseHexColor(self: *Parser) Error!u32 {
        try self.expect('0');
        try self.expect('x');
        const start = self.pos;
        while (self.pos < self.source.len and std.ascii.isHex(self.source[self.pos])) {
            self.pos += 1;
        }
        const hex = self.source[start..self.pos];
        return std.fmt.parseInt(u32, hex, 16) catch return Error.InvalidSyntax;
    }

    fn parseString(self: *Parser) Error![]const u8 {
        try self.expect('"');
        const start = self.pos;
        while (self.pos < self.source.len and self.source[self.pos] != '"') {
            if (self.source[self.pos] == '\\') self.pos += 1;
            self.pos += 1;
        }
        const value = try self.allocator.dupe(u8, self.source[start..self.pos]);
        try self.expect('"');
        return value;
    }

    fn parseNumber(self: *Parser) Error!u32 {
        const start = self.pos;
        while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
            self.pos += 1;
        }
        return std.fmt.parseInt(u32, self.source[start..self.pos], 10) catch return Error.InvalidSyntax;
    }

    fn parseBool(self: *Parser) Error!bool {
        if (self.source.len > self.pos + 4 and std.mem.eql(u8, self.source[self.pos..][0..4], "true")) {
            self.pos += 4;
            return true;
        } else if (self.source.len > self.pos + 5 and std.mem.eql(u8, self.source[self.pos..][0..5], "false")) {
            self.pos += 5;
            return false;
        }
        return Error.InvalidSyntax;
    }

    fn parseIdentifier(self: *Parser) Error![]const u8 {
        const start = self.pos;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                self.pos += 1;
            } else {
                break;
            }
        }
        if (self.pos == start) return Error.InvalidSyntax;
        return self.source[start..self.pos];
    }

    fn expect(self: *Parser, expected: u8) Error!void {
        if (self.pos >= self.source.len) return Error.UnexpectedEof;
        if (self.source[self.pos] != expected) return Error.UnexpectedToken;
        self.pos += 1;
    }

    fn peek(self: *Parser) u8 {
        if (self.pos >= self.source.len) return 0;
        return self.source[self.pos];
    }

    fn skipWhitespaceAndComments(self: *Parser) void {
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.pos += 1;
            } else if (c == '/' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '/') {
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }
};

/// Load settings from config.zon
pub fn load(allocator: Allocator, path: []const u8) !Settings {
    const file = std.fs.cwd().openFile(path, .{}) catch {
        // Return defaults if no config file
        return Settings{
            .allocator = allocator,
            .leader_key = try allocator.dupe(u8, "super"),
            .font = .{ .family = try allocator.dupe(u8, "monospace") },
        };
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    var parser = Parser.init(allocator, source);
    return parser.parse();
}

test "parse settings" {
    const source =
        \\.{
        \\    .leader_key = "alt",
        \\    .theme = .gruvbox,
        \\}
    ;
    var parser = Parser.init(std.testing.allocator, source);
    var settings = try parser.parse();
    defer settings.deinit();

    try std.testing.expectEqualStrings("alt", settings.leader_key);
    try std.testing.expectEqual(presets.gruvbox.bg, settings.theme.bg);
}
