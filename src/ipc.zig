//! Basket IPC module
//!
//! Provides external control of basket via unix socket.

pub const Server = @import("ipc/server.zig");
pub const action_parser = @import("ipc/action_parser.zig");
