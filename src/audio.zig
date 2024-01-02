const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

const IoMethod = @import("console.zig").IoMethod;

pub fn Context(comptime method: IoMethod) type {
    switch (method) {
        .pure => return PureContext,
        .sdl => return @import("sdl/audio.zig").Context,
    }
}

pub const PureContext = struct {
    allocator: Allocator,
    bytes: ArrayList(f32),

    pub const sample_rate = 44100 / 2;

    pub fn init(allocator: Allocator) !PureContext {
        return PureContext{
            .allocator = allocator,
            .bytes = ArrayList(f32){},
        };
    }

    pub fn deinit(self: *PureContext, _: Allocator) void {
        self.bytes.deinit(self.allocator);
    }
    pub fn addSample(self: *PureContext, val: f32) !void {
        try self.bytes.append(self.allocator, val);
    }
};
