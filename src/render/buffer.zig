//! Shared memory buffer management for Wayland surfaces
//!
//! Creates and manages wl_shm pools and buffers for rendering.

const std = @import("std");
const wayland = @import("wayland");
const wl = wayland.client.wl;
const os = std.os;

pub const ShmBuffer = struct {
    shm: *wl.Shm,
    pool: ?*wl.ShmPool = null,
    buffer: ?*wl.Buffer = null,
    data: ?[]align(4096) u8 = null,
    fd: ?std.posix.fd_t = null,
    width: u32,
    height: u32,
    stride: u32,

    const BYTES_PER_PIXEL = 4; // ARGB8888

    pub fn init(shm: *wl.Shm, width: u32, height: u32) ShmBuffer {
        return .{
            .shm = shm,
            .width = width,
            .height = height,
            .stride = width * BYTES_PER_PIXEL,
        };
    }

    pub fn create(self: *ShmBuffer) !void {
        const size = self.stride * self.height;

        // Create anonymous file for shared memory
        const fd = try std.posix.memfd_create("deltas-buffer", 0);
        errdefer std.posix.close(fd);

        // Size the file
        try std.posix.ftruncate(fd, @intCast(size));

        // Map it
        const data = try std.posix.mmap(
            null,
            size,
            std.posix.PROT.READ | std.posix.PROT.WRITE,
            .{ .TYPE = .SHARED },
            fd,
            0,
        );

        self.fd = fd;
        self.data = @alignCast(data);

        // Create wl_shm_pool
        self.pool = self.shm.createPool(fd, @intCast(size)) catch return error.CreatePoolFailed;

        // Create wl_buffer from pool
        self.buffer = self.pool.?.createBuffer(
            0, // offset
            @intCast(self.width),
            @intCast(self.height),
            @intCast(self.stride),
            .argb8888,
        ) catch return error.CreateBufferFailed;

        // Set up buffer listener for release events
        self.buffer.?.setListener(*ShmBuffer, bufferListener, self);
    }

    pub fn destroy(self: *ShmBuffer) void {
        if (self.buffer) |b| b.destroy();
        if (self.pool) |p| p.destroy();
        if (self.data) |d| std.posix.munmap(d);
        if (self.fd) |fd| std.posix.close(fd);
    }

    fn bufferListener(buffer: *wl.Buffer, event: wl.Buffer.Event, self: *ShmBuffer) void {
        _ = buffer;
        _ = self;
        switch (event) {
            .release => {
                // Buffer is no longer in use by compositor
                // Can safely reuse or destroy
            },
        }
    }

    /// Fill buffer with solid color (ARGB format)
    pub fn fill(self: *ShmBuffer, color: u32) void {
        if (self.data) |data| {
            const pixel_data = std.mem.bytesAsSlice(u32, data);
            @memset(pixel_data, color);
        }
    }

    /// Get pixel data for direct manipulation
    pub fn pixels(self: *ShmBuffer) ?[]u32 {
        if (self.data) |data| {
            return std.mem.bytesAsSlice(u32, data);
        }
        return null;
    }

    /// Get the wl_buffer for attaching to surface
    pub fn getBuffer(self: *ShmBuffer) ?*wl.Buffer {
        return self.buffer;
    }
};
