const std = @import("std");
const Allocator = std.mem.Allocator;

const PixelBuffer = @import("video.zig").PixelBuffer;

pub const ImguiContext = struct {
    pixel_buffer: PixelBuffer,

    pub fn init(allocator: *Allocator) !ImguiContext {
        return ImguiContext{
            .pixel_buffer = try PixelBuffer.init(allocator, 256, 240),
        };
    }

    pub fn deinit(self: ImguiContext, allocator: *Allocator) void {
        self.pixel_buffer.deinit(allocator);
    }

    pub fn getPixelBuffer(self: *ImguiContext) *PixelBuffer {
        return &self.pixel_buffer;
    }

    pub fn draw(self: *ImguiContext) !void {
        _ = self;
    }
};
