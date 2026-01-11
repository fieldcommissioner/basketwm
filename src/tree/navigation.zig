//! Key tree navigation and state machine
//!
//! Handles:
//!   - Tree traversal (key → child node)
//!   - Mode stack (sticky menus push, ESC pops)
//!   - Transient vs sticky behavior per-node
//!   - Dispatch to shell commands OR compiled functions (kwm)

const std = @import("std");

pub const NodeType = enum {
    action,   // leaf: execute command
    submenu,  // branch: has children
};

pub const MenuBehavior = enum {
    transient, // close after action
    sticky,    // stay open until ESC
};

/// How to execute an action
pub const ActionHandler = union(enum) {
    /// Shell command to spawn
    shell: []const u8,

    /// Direct function pointer (for compiled WM actions)
    dispatch: *const fn () void,

    /// No action (display-only node)
    none,
};

pub const Node = struct {
    key: u8,                          // triggering key
    label: []const u8,                // display text
    hint: ?[]const u8 = null,         // right-aligned hint (value, shortcut, etc.)
    node_type: NodeType,
    behavior: MenuBehavior = .transient,
    repeat: bool = false,             // allow rapid re-trigger in sticky mode

    // For action nodes
    handler: ActionHandler = .none,

    // Legacy compat - will be removed
    action: ?[]const u8 = null,

    // For submenu nodes
    children: ?[]const Node = null,

    pub fn isLeaf(self: *const Node) bool {
        return self.node_type == .action;
    }

    /// Execute this node's action
    pub fn execute(self: *const Node) void {
        switch (self.handler) {
            .dispatch => |func| func(),
            .shell => |cmd| {
                // TODO: spawn shell command
                std.debug.print("spawn: {s}\n", .{cmd});
            },
            .none => {
                // Legacy fallback
                if (self.action) |cmd| {
                    std.debug.print("spawn: {s}\n", .{cmd});
                }
            },
        }
    }
};

pub const Navigator = struct {
    root: *const Node,
    current: *const Node,
    mode_stack: std.ArrayListUnmanaged(*const Node),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, root: *const Node) Navigator {
        return Navigator{
            .root = root,
            .current = root,
            .mode_stack = .{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Navigator) void {
        self.mode_stack.deinit(self.allocator);
    }

    pub fn handleKey(self: *Navigator, key: u8) ?NavAction {
        // ESC: pop mode stack or close
        if (key == 27) { // ESC
            return self.popOrClose();
        }

        // Find matching child
        if (self.current.children) |children| {
            for (children) |*child| {
                if (child.key == key) {
                    return self.activate(child);
                }
            }
        }

        // No match - ignore or beep
        return null;
    }

    fn activate(self: *Navigator, node: *const Node) ?NavAction {
        switch (node.node_type) {
            .action => {
                // Execute the action
                node.execute();

                // After action: close or stay based on behavior
                if (node.behavior == .transient and !node.repeat) {
                    return NavAction{ .execute_and_close = node };
                }
                return NavAction{ .execute = node };
            },
            .submenu => {
                if (node.behavior == .sticky) {
                    self.mode_stack.append(self.allocator, self.current) catch {};
                }
                self.current = node;
                return NavAction{ .show_menu = node };
            },
        }
    }

    fn popOrClose(self: *Navigator) ?NavAction {
        if (self.mode_stack.pop()) |prev| {
            self.current = prev;
            return NavAction{ .show_menu = self.current };
        }
        self.current = self.root;
        return NavAction.close;
    }
};

/// Result of navigation - what the UI should do
pub const NavAction = union(enum) {
    /// Execute action, keep menu open (for repeatable)
    execute: *const Node,

    /// Execute action and close menu
    execute_and_close: *const Node,

    /// Show a submenu
    show_menu: *const Node,

    /// Close the menu entirely
    close,
};

test "navigation placeholder" {
    try std.testing.expect(true);
}
