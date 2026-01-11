//! Configuration loader for basket delta layer (chord trees)
//!
//! Doom-style configuration:
//!
//!   ~/.config/basket/
//!   ├── delta.zon         # chord tree root (newcomer-friendly)
//!   ├── +window.zon       # injects at 'w'
//!   ├── +apps.zon         # injects at 'o' (open)
//!   ├── +git.zon          # injects at 'g'
//!   └── basket.zon        # combo overrides (ricer territory)
//!
//! Module injection:
//!   - Filename +X.zon → injects at key 'X'
//!   - Filename +X-Y.zon → injects at key path X → Y
//!   - Or explicit: .inject_at = "w" in the file
//!
//! Merge order: delta.zon first, then +modules alphabetically.
//! Later files can override earlier ones (user wins).

const std = @import("std");
const tree = @import("../tree/navigation.zig");
const zon = @import("zon.zig");
pub const settings = @import("settings.zig");

pub const Settings = settings.Settings;
pub const Theme = settings.Theme;
pub const Font = settings.Font;
pub const presets = settings.presets;

pub const Config = struct {
    leader_key: []const u8 = "super",
    timeout_ms: u32 = 500,
    root: ?*tree.Node = null,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Config) void {
        if (self.root) |root| {
            freeNode(self.allocator, root);
        }
    }

    fn freeNode(allocator: std.mem.Allocator, node: *const tree.Node) void {
        allocator.free(node.label);
        if (node.children) |children| {
            for (children) |*child| {
                freeNodeInline(allocator, child);
            }
            allocator.free(children);
        }
        allocator.destroy(@constCast(node));
    }

    fn freeNodeInline(allocator: std.mem.Allocator, node: *const tree.Node) void {
        allocator.free(node.label);
        if (node.children) |children| {
            for (children) |*child| {
                freeNodeInline(allocator, child);
            }
            allocator.free(children);
        }
    }
};

pub const Loader = struct {
    allocator: std.mem.Allocator,
    config_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator, config_dir: []const u8) Loader {
        return .{
            .allocator = allocator,
            .config_dir = config_dir,
        };
    }

    /// Load all config files and merge into final tree
    pub fn load(self: *Loader) !Config {
        var config = Config{
            .allocator = self.allocator,
        };

        // Try to load delta.zon first (chord tree root)
        const delta_path = try std.fs.path.join(self.allocator, &.{ self.config_dir, "delta.zon" });
        defer self.allocator.free(delta_path);

        if (zon.loadConfig(self.allocator, delta_path)) |module| {
            var mod = module;
            defer mod.deinit(self.allocator);

            if (mod.leader_key) |lk| config.leader_key = lk;
            config.timeout_ms = mod.timeout_ms;

            // Convert to tree
            config.root = try self.buildRootNode(&mod);
        } else |_| {
            // No leader.zon, create empty root
            config.root = try self.createEmptyRoot();
        }

        // Scan for +module.zon files
        try self.loadModules(&config);

        return config;
    }

    fn buildRootNode(self: *Loader, module: *zon.ModuleConfig) !*tree.Node {
        const root = try self.allocator.create(tree.Node);
        root.* = .{
            .key = ' ', // leader key
            .label = try self.allocator.dupe(u8, module.label orelse "basket"),
            .node_type = .submenu,
            .behavior = .transient,
            .children = try self.convertChildren(module.children),
        };
        return root;
    }

    fn createEmptyRoot(self: *Loader) !*tree.Node {
        const root = try self.allocator.create(tree.Node);
        root.* = .{
            .key = ' ',
            .label = try self.allocator.dupe(u8, "basket"),
            .node_type = .submenu,
            .behavior = .transient,
            .children = null,
        };
        return root;
    }

    fn convertChildren(self: *Loader, config_nodes: []zon.ConfigNode) ![]tree.Node {
        var nodes = try self.allocator.alloc(tree.Node, config_nodes.len);
        for (config_nodes, 0..) |*cn, i| {
            nodes[i] = try cn.toTreeNode(self.allocator);
        }
        return nodes;
    }

    fn loadModules(self: *Loader, config: *Config) !void {
        var dir = std.fs.cwd().openDir(self.config_dir, .{ .iterate = true }) catch return;
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (entry.name.len < 5) continue; // +X.zon minimum
            if (entry.name[0] != '+') continue;
            if (!std.mem.endsWith(u8, entry.name, ".zon")) continue;

            // Extract injection path from filename
            // +window.zon → "w" (first char after +)
            // +w-r.zon → "w-r" (path w → r)
            const base = entry.name[1 .. entry.name.len - 4]; // strip + and .zon
            if (base.len == 0) continue;

            const full_path = try std.fs.path.join(self.allocator, &.{ self.config_dir, entry.name });
            defer self.allocator.free(full_path);

            if (zon.loadConfig(self.allocator, full_path)) |module| {
                var mod = module;
                defer mod.deinit(self.allocator);

                // Determine injection point
                const inject_at = mod.inject_at orelse base;

                // Inject into tree
                try self.injectModule(config.root.?, inject_at, &mod);
            } else |_| {
                std.debug.print("[config] failed to load: {s}\n", .{entry.name});
            }
        }
    }

    fn injectModule(self: *Loader, root: *tree.Node, path: []const u8, module: *zon.ModuleConfig) !void {
        // Parse path: "w" or "w-r" for nested
        var parts = std.mem.splitScalar(u8, path, '-');
        var current: *tree.Node = root;

        while (parts.next()) |part| {
            if (part.len == 0) continue;
            const key = part[0];

            // Find or create child with this key
            current = try self.findOrCreateChild(current, key, part);
        }

        // Merge module children into current node
        try self.mergeChildren(current, module.children);
    }

    fn findOrCreateChild(self: *Loader, parent: *tree.Node, key: u8, label: []const u8) !*tree.Node {
        // Look for existing child (we own this memory so cast is safe)
        if (parent.children) |children| {
            const mutable_children = @constCast(children);
            for (mutable_children) |*child| {
                if (child.key == key) {
                    return child;
                }
            }
        }

        // Create new child
        const new_child = tree.Node{
            .key = key,
            .label = try self.allocator.dupe(u8, label),
            .node_type = .submenu,
            .behavior = .transient,
            .children = null,
        };

        // Append to parent's children
        if (parent.children) |children| {
            var new_children = try self.allocator.alloc(tree.Node, children.len + 1);
            @memcpy(new_children[0..children.len], children);
            new_children[children.len] = new_child;
            self.allocator.free(children);
            parent.children = new_children;
        } else {
            var new_children = try self.allocator.alloc(tree.Node, 1);
            new_children[0] = new_child;
            parent.children = new_children;
        }

        return @constCast(&parent.children.?[parent.children.?.len - 1]);
    }

    fn mergeChildren(self: *Loader, target: *tree.Node, source: []zon.ConfigNode) !void {
        for (source) |*src| {
            // Check if child with same key exists
            var found = false;
            if (target.children) |children| {
                const mutable_children = @constCast(children);
                for (mutable_children) |*child| {
                    if (child.key == src.key) {
                        // Override existing
                        // For now, just replace - could deep merge later
                        child.label = try self.allocator.dupe(u8, src.label);
                        child.behavior = src.behavior;
                        child.repeat = src.repeat;
                        if (src.action) |action| {
                            child.handler = .{ .shell = try self.allocator.dupe(u8, action) };
                            child.node_type = .action;
                        }
                        if (src.children) |src_children| {
                            try self.mergeChildren(child, src_children);
                        }
                        found = true;
                        break;
                    }
                }
            }

            if (!found) {
                // Add new child
                const new_child = try src.toTreeNode(self.allocator);
                if (target.children) |children| {
                    var new_children = try self.allocator.alloc(tree.Node, children.len + 1);
                    @memcpy(new_children[0..children.len], children);
                    new_children[children.len] = new_child;
                    self.allocator.free(children);
                    target.children = new_children;
                } else {
                    var new_children = try self.allocator.alloc(tree.Node, 1);
                    new_children[0] = new_child;
                    target.children = new_children;
                }
            }
        }
    }
};

/// Convenience function
pub fn load(allocator: std.mem.Allocator, config_dir: []const u8) !Config {
    var loader = Loader.init(allocator, config_dir);
    return loader.load();
}

/// Get default config directory
pub fn getConfigDir(allocator: std.mem.Allocator) ![]const u8 {
    // XDG_CONFIG_HOME or ~/.config
    if (std.posix.getenv("XDG_CONFIG_HOME")) |xdg| {
        return std.fs.path.join(allocator, &.{ xdg, "basket" });
    }
    if (std.posix.getenv("HOME")) |home| {
        return std.fs.path.join(allocator, &.{ home, ".config", "basket" });
    }
    return error.NoHomeDir;
}

/// Load global settings from config.zon
pub fn loadSettings(allocator: std.mem.Allocator, config_dir: []const u8) !Settings {
    const path = try std.fs.path.join(allocator, &.{ config_dir, "config.zon" });
    defer allocator.free(path);
    return settings.load(allocator, path);
}

test "loader init" {
    const loader = Loader.init(std.testing.allocator, "/tmp/test");
    try std.testing.expectEqualStrings("/tmp/test", loader.config_dir);
}
