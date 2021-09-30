const std = @import("std");
const Allocator = std.mem.Allocator;

const IoMethod = @import("console.zig").IoMethod;

pub fn Context(comptime method: IoMethod) type {
    switch (method) {
        .pure => return PureContext,
        .sdl => return @import("sdl/video.zig").Context,
    }
}

pub fn FrameBuffer(comptime method: IoMethod) type {
    return @TypeOf(@as(Context(method), undefined).frame_buffer);
}

pub const PureContext = struct {
    frame_buffer: Fb,

    const Fb = struct {
        pixels: []u32,

        pub fn init(allocator: *Allocator) !Fb {
            return Fb{
                .pixels = try allocator.alloc(u32, 256 * 240),
            };
        }

        pub fn deinit(self: Fb, allocator: *Allocator) void {
            allocator.free(self.pixels);
        }

        pub fn putPixel(self: Fb, x: usize, y: usize, pixel: u32) void {
            self.pixels[x + y * 256] = pixel;
        }
    };

    pub fn init(allocator: *Allocator) !PureContext {
        return PureContext{
            .frame_buffer = try Fb.init(allocator),
        };
    }

    pub fn deinit(self: PureContext, allocator: *Allocator) void {
        self.frame_buffer.deinit(allocator);
    }
};
