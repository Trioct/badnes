const std = @import("std");
const Allocator = std.mem.Allocator;

const IoMethod = @import("console.zig").IoMethod;

pub const VideoMethod = enum {
    pure,
    sdl_basic,
    sdl_imgui,
};

pub fn Context(comptime method: VideoMethod) type {
    switch (method) {
        .pure => return PureContext,
        .sdl_basic => return @import("sdl/video.zig").Context(false),
        .sdl_imgui => return @import("sdl/video.zig").Context(true),
    }
}

pub fn PixelBuffer(comptime method: IoMethod) type {
    switch (method) {
        .pure => return PureContext.Pb,
        .sdl => return @import("sdl/video.zig").PixelBuffer,
    }
}

pub const PureContext = struct {
    pixel_buffer: Pb,

    const Pb = struct {
        pixels: []u32,

        pub fn init(allocator: *Allocator) !Pb {
            return Pb{
                .pixels = try allocator.alloc(u32, 256 * 240),
            };
        }

        pub fn deinit(self: Pb, allocator: *Allocator) void {
            allocator.free(self.pixels);
        }

        pub fn putPixel(self: Pb, x: usize, y: usize, pixel: u32) void {
            self.pixels[x + y * 256] = pixel;
        }
    };

    pub fn init(allocator: *Allocator) !PureContext {
        return PureContext{
            .pixel_buffer = try Pb.init(allocator),
        };
    }

    pub fn deinit(self: PureContext, allocator: *Allocator) void {
        self.pixel_buffer.deinit(allocator);
    }

    pub fn getPixelBuffer(self: *PureContext) *Pb {
        return &self.pixel_buffer;
    }
};
