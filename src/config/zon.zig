//! ZON config parser for Deltas
//!
//! Parses .zon files at runtime into menu tree structures.
//! Supports the Doom-style +module injection pattern.

const std = @import("std");
const Allocator = std.mem.Allocator;
const tree = @import("../tree/navigation.zig");

pub const ParseError = error{
    UnexpectedToken,
    InvalidSyntax,
    UnexpectedEof,
    InvalidKey,
    OutOfMemory,
    InvalidUtf8,
};

pub const ConfigNode = struct {
    key: u8,
    label: []const u8,
    action: ?[]const u8 = null,
    behavior: tree.MenuBehavior = .transient,
    repeat: bool = false,
    children: ?[]ConfigNode = null,

    /// Convert to runtime tree node
    pub fn toTreeNode(self: *const ConfigNode, allocator: Allocator) !tree.Node {
        var node = tree.Node{
            .key = self.key,
            .label = try allocator.dupe(u8, self.label),
            .node_type = if (self.children != null) .submenu else .action,
            .behavior = self.behavior,
            .repeat = self.repeat,
            .handler = if (self.action) |cmd|
                .{ .shell = try allocator.dupe(u8, cmd) }
            else
                .none,
            .children = null,
        };

        if (self.children) |children| {
            var tree_children = try allocator.alloc(tree.Node, children.len);
            for (children, 0..) |child, i| {
                tree_children[i] = try child.toTreeNode(allocator);
            }
            node.children = tree_children;
        }

        return node;
    }

    pub fn deinit(self: *ConfigNode, allocator: Allocator) void {
        allocator.free(self.label);
        if (self.action) |a| allocator.free(a);
        if (self.children) |children| {
            for (children) |*child| {
                child.deinit(allocator);
            }
            allocator.free(children);
        }
    }
};

pub const ModuleConfig = struct {
    /// Where to inject (e.g., "w" or "w-r" for nested)
    inject_at: ?[]const u8 = null,
    /// Root label (for leader.zon)
    label: ?[]const u8 = null,
    /// Leader key config
    leader_key: ?[]const u8 = null,
    /// Timeout for which-key popup
    timeout_ms: u32 = 500,
    /// Children nodes
    children: []ConfigNode,

    pub fn deinit(self: *ModuleConfig, allocator: Allocator) void {
        if (self.inject_at) |ia| allocator.free(ia);
        if (self.label) |l| allocator.free(l);
        if (self.leader_key) |lk| allocator.free(lk);
        for (self.children) |*child| {
            child.deinit(allocator);
        }
        allocator.free(self.children);
    }
};

pub const Parser = struct {
    allocator: Allocator,
    source: []const u8,
    pos: usize = 0,

    const NodeList = std.ArrayListUnmanaged(ConfigNode);
    const Error = ParseError || Allocator.Error;

    pub fn init(allocator: Allocator, source: []const u8) Parser {
        return .{
            .allocator = allocator,
            .source = source,
        };
    }

    pub fn parseModule(self: *Parser) !ModuleConfig {
        self.skipWhitespaceAndComments();
        try self.expect('.');
        try self.expect('{');

        var config = ModuleConfig{
            .children = &.{},
        };

        var children: NodeList = .{};
        errdefer {
            for (children.items) |*child| child.deinit(self.allocator);
            children.deinit(self.allocator);
        }

        while (true) {
            self.skipWhitespaceAndComments();
            if (self.peek() == '}') {
                self.pos += 1;
                break;
            }

            // Parse field
            try self.expect('.');
            const field_name = try self.parseIdentifier();

            self.skipWhitespaceAndComments();
            try self.expect('=');
            self.skipWhitespaceAndComments();

            if (std.mem.eql(u8, field_name, "inject_at")) {
                config.inject_at = try self.parseString();
            } else if (std.mem.eql(u8, field_name, "label")) {
                config.label = try self.parseString();
            } else if (std.mem.eql(u8, field_name, "key") or std.mem.eql(u8, field_name, "leader_key")) {
                config.leader_key = try self.parseString();
            } else if (std.mem.eql(u8, field_name, "timeout_ms")) {
                config.timeout_ms = try self.parseNumber();
            } else if (std.mem.eql(u8, field_name, "children")) {
                children = try self.parseNodeArray();
            } else if (std.mem.eql(u8, field_name, "position")) {
                // Skip position for now
                _ = try self.parseValue();
            }

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') self.pos += 1;
        }

        config.children = try children.toOwnedSlice(self.allocator);
        return config;
    }

    fn parseNodeArray(self: *Parser) Error!NodeList {
        var nodes: NodeList = .{};
        errdefer {
            for (nodes.items) |*node| node.deinit(self.allocator);
            nodes.deinit(self.allocator);
        }

        try self.expect('.');
        try self.expect('{');

        while (true) {
            self.skipWhitespaceAndComments();
            if (self.peek() == '}') {
                self.pos += 1;
                break;
            }

            const node = try self.parseNode();
            try nodes.append(self.allocator, node);

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') self.pos += 1;
        }

        return nodes;
    }

    fn parseNode(self: *Parser) Error!ConfigNode {
        try self.expect('.');
        try self.expect('{');

        var node = ConfigNode{
            .key = 0,
            .label = "",
        };

        var children: NodeList = .{};
        errdefer {
            for (children.items) |*child| child.deinit(self.allocator);
            children.deinit(self.allocator);
        }

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

            if (std.mem.eql(u8, field, "key")) {
                node.key = try self.parseChar();
            } else if (std.mem.eql(u8, field, "label")) {
                node.label = try self.parseString();
            } else if (std.mem.eql(u8, field, "action")) {
                node.action = try self.parseString();
            } else if (std.mem.eql(u8, field, "behavior")) {
                node.behavior = try self.parseBehavior();
            } else if (std.mem.eql(u8, field, "repeat")) {
                node.repeat = try self.parseBool();
            } else if (std.mem.eql(u8, field, "children")) {
                children = try self.parseNodeArray();
            }

            self.skipWhitespaceAndComments();
            if (self.peek() == ',') self.pos += 1;
        }

        if (children.items.len > 0) {
            node.children = try children.toOwnedSlice(self.allocator);
        } else {
            children.deinit(self.allocator);
        }

        return node;
    }

    fn parseChar(self: *Parser) !u8 {
        if (self.peek() == '\'') {
            self.pos += 1;
            const c = self.source[self.pos];
            self.pos += 1;
            try self.expect('\'');
            return c;
        }
        return ParseError.InvalidSyntax;
    }

    fn parseString(self: *Parser) ![]const u8 {
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

    fn parseNumber(self: *Parser) !u32 {
        const start = self.pos;
        while (self.pos < self.source.len and std.ascii.isDigit(self.source[self.pos])) {
            self.pos += 1;
        }
        return std.fmt.parseInt(u32, self.source[start..self.pos], 10) catch return ParseError.InvalidSyntax;
    }

    fn parseBool(self: *Parser) !bool {
        if (self.source.len > self.pos + 4 and std.mem.eql(u8, self.source[self.pos..][0..4], "true")) {
            self.pos += 4;
            return true;
        } else if (self.source.len > self.pos + 5 and std.mem.eql(u8, self.source[self.pos..][0..5], "false")) {
            self.pos += 5;
            return false;
        }
        return ParseError.InvalidSyntax;
    }

    fn parseBehavior(self: *Parser) !tree.MenuBehavior {
        try self.expect('.');
        const name = try self.parseIdentifier();
        if (std.mem.eql(u8, name, "sticky")) return .sticky;
        return .transient;
    }

    fn parseValue(self: *Parser) !void {
        // Skip any value (for fields we don't care about)
        const c = self.peek();
        if (c == '.') {
            self.pos += 1;
            _ = try self.parseIdentifier();
        } else if (c == '"') {
            const s = try self.parseString();
            self.allocator.free(s);
        } else if (std.ascii.isDigit(c)) {
            _ = try self.parseNumber();
        }
    }

    fn parseIdentifier(self: *Parser) ![]const u8 {
        const start = self.pos;
        while (self.pos < self.source.len) {
            const c = self.source[self.pos];
            if (std.ascii.isAlphanumeric(c) or c == '_') {
                self.pos += 1;
            } else {
                break;
            }
        }
        if (self.pos == start) return ParseError.InvalidSyntax;
        return self.source[start..self.pos];
    }

    fn expect(self: *Parser, expected: u8) !void {
        if (self.pos >= self.source.len) return ParseError.UnexpectedEof;
        if (self.source[self.pos] != expected) return ParseError.UnexpectedToken;
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
                // Line comment
                while (self.pos < self.source.len and self.source[self.pos] != '\n') {
                    self.pos += 1;
                }
            } else {
                break;
            }
        }
    }
};

/// Load and parse a .zon config file
pub fn loadConfig(allocator: Allocator, path: []const u8) !ModuleConfig {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    var parser = Parser.init(allocator, source);
    return parser.parseModule();
}

test "parse simple node" {
    const source =
        \\.{
        \\    .key = 'w',
        \\    .label = "window",
        \\}
    ;
    var parser = Parser.init(std.testing.allocator, source);
    var node = try parser.parseNode();
    defer node.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u8, 'w'), node.key);
    try std.testing.expectEqualStrings("window", node.label);
}
