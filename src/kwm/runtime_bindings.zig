//! Runtime keybinding storage
//!
//! Holds keybindings that are loaded at runtime (from defaults + basket.zon)
//! instead of compile-time config.zig bindings.
//!
//! This allows the doom-style configuration:
//! - defaults.zig provides sane defaults
//! - basket.zon can unbind/rebind at runtime
//! - Seat.create() uses these instead of config.xkb_bindings

const std = @import("std");
const binding = @import("binding.zig");
const config = @import("config");

/// Runtime XKB binding entry (matches config.zig XkbBinding structure)
pub const RuntimeXkbBinding = struct {
    keysym: u32,
    modifiers: u32,
    action: binding.Action,
    mode: config.Mode = .default,
    event: @import("wayland").client.river.XkbBindingV1.Event = .pressed,
};

/// Runtime pointer binding entry
pub const RuntimePointerBinding = struct {
    button: u32,
    modifiers: u32,
    action: binding.Action,
    mode: config.Mode = .default,
    event: @import("wayland").client.river.PointerBindingV1.Event = .pressed,
};

/// Global storage for runtime bindings
/// Set by main.zig before seats are created
var runtime_xkb_bindings: ?[]const RuntimeXkbBinding = null;
var runtime_pointer_bindings: ?[]const RuntimePointerBinding = null;
var use_runtime_bindings: bool = false;

/// Set runtime XKB bindings (called from main.zig)
pub fn setXkbBindings(bindings: []const RuntimeXkbBinding) void {
    runtime_xkb_bindings = bindings;
    use_runtime_bindings = true;
}

/// Set runtime pointer bindings (called from main.zig)
pub fn setPointerBindings(bindings: []const RuntimePointerBinding) void {
    runtime_pointer_bindings = bindings;
}

/// Check if runtime bindings are active
pub fn isEnabled() bool {
    return use_runtime_bindings;
}

/// Get runtime XKB bindings, or null if using config.zig
pub fn getXkbBindings() ?[]const RuntimeXkbBinding {
    return runtime_xkb_bindings;
}

/// Get runtime pointer bindings, or null if using config.zig
pub fn getPointerBindings() ?[]const RuntimePointerBinding {
    return runtime_pointer_bindings;
}

/// Iterator that works over either runtime or config bindings
pub const XkbBindingIterator = struct {
    runtime_bindings: ?[]const RuntimeXkbBinding,
    index: usize = 0,

    pub fn next(self: *XkbBindingIterator) ?RuntimeXkbBinding {
        if (self.runtime_bindings) |bindings| {
            if (self.index >= bindings.len) return null;
            defer self.index += 1;
            return bindings[self.index];
        }
        // Fallback to config.xkb_bindings
        if (self.index >= config.xkb_bindings.len) return null;
        defer self.index += 1;
        const cb = &config.xkb_bindings[self.index];
        return RuntimeXkbBinding{
            .keysym = cb.keysym,
            .modifiers = cb.modifiers,
            .action = cb.action,
            .mode = cb.mode,
            .event = cb.event,
        };
    }
};

pub const PointerBindingIterator = struct {
    runtime_bindings: ?[]const RuntimePointerBinding,
    index: usize = 0,

    pub fn next(self: *PointerBindingIterator) ?RuntimePointerBinding {
        if (self.runtime_bindings) |bindings| {
            if (self.index >= bindings.len) return null;
            defer self.index += 1;
            return bindings[self.index];
        }
        // Fallback to config.pointer_bindings
        if (self.index >= config.pointer_bindings.len) return null;
        defer self.index += 1;
        const cb = &config.pointer_bindings[self.index];
        return RuntimePointerBinding{
            .button = cb.button,
            .modifiers = cb.modifiers,
            .action = cb.action,
            .mode = cb.mode,
            .event = cb.event,
        };
    }
};

/// Get an iterator over XKB bindings (runtime or config fallback)
pub fn xkbBindings() XkbBindingIterator {
    return .{ .runtime_bindings = runtime_xkb_bindings };
}

/// Get an iterator over pointer bindings (runtime or config fallback)
pub fn pointerBindings() PointerBindingIterator {
    return .{ .runtime_bindings = runtime_pointer_bindings };
}
