const std = @import("std");
const time = std.time;

const sdl = @import("bindings.zig");

pub const Context = struct {
    window: *sdl.Window,
    renderer: *sdl.Renderer,
    frame_buffer: FrameBuffer,

    last_frame_time: i128,
    next_frame_time: i128,

    pub fn init(title: [:0]const u8, x: u31, y: u31, w: u31, h: u31) !Context {
        const window = try sdl.createWindow(.{
            title,
            @as(c_int, x),
            @as(c_int, y),
            @as(c_int, w),
            @as(c_int, h),
            sdl.c.SDL_WINDOW_SHOWN,
        });
        errdefer sdl.destroyWindow(.{window});

        const renderer = try sdl.createRenderer(.{ window, -1, sdl.c.SDL_RENDERER_ACCELERATED });
        const now = time.nanoTimestamp();

        return Context{
            .window = window,
            .renderer = renderer,
            .frame_buffer = try FrameBuffer.init(renderer, 256, 240),

            .last_frame_time = now,
            .next_frame_time = now,
        };
    }

    pub fn deinit(self: Context) void {
        self.frame_buffer.deinit();
        sdl.destroyRenderer(.{self.renderer});
        sdl.destroyWindow(.{self.window});
    }

    pub const DrawOptions = struct {
        timing: enum {
            Untimed,
            Timed,
        },
        // ~1/60
        frametime: f32 = (4 * (261 * 341 + 340.5)) / 21477272.0,
    };

    pub fn drawFrame(self: *Context, draw_options: DrawOptions) !i128 {
        try self.frame_buffer.present(self.renderer);

        const frame_ns = @floatToInt(i128, time.ns_per_s * draw_options.frametime);
        const now = time.nanoTimestamp();
        const to_sleep = self.next_frame_time - now;
        var passed = now - self.last_frame_time;

        switch (draw_options.timing) {
            .Untimed => {},
            .Timed => if (to_sleep > 0) {
                time.sleep(@intCast(u64, to_sleep));
                passed += to_sleep;
            },
        }

        self.next_frame_time += frame_ns;
        self.last_frame_time += passed;

        return passed;
    }
};

pub const FrameBuffer = struct {
    texture: *sdl.Texture,
    pixels: ?[]u32 = null,
    width: usize,
    pixel_count: usize,

    pub fn init(renderer: *sdl.Renderer, width: usize, height: usize) !FrameBuffer {
        const texture = try sdl.createTexture(.{
            renderer,
            sdl.c.SDL_PIXELFORMAT_RGB888, // consider RGB24?
            sdl.c.SDL_TEXTUREACCESS_STREAMING,
            @intCast(c_int, width),
            @intCast(c_int, height),
        });
        var fb =
            FrameBuffer{
            .texture = texture,
            .width = width,
            .pixel_count = width * height,
        };
        try fb.lock();
        return fb;
    }

    pub fn deinit(self: FrameBuffer) void {
        sdl.destroyTexture(.{self.texture});
    }

    pub fn lock(self: *FrameBuffer) !void {
        var pixels: ?*c_void = undefined;
        var pitch: c_int = undefined;
        try sdl.lockTexture(.{ self.texture, null, &pixels, &pitch });
        if (pixels) |ptr| {
            self.pixels = @ptrCast([*]u32, @alignCast(4, ptr))[0..self.pixel_count];
        }
    }

    pub fn unlock(self: FrameBuffer) void {
        sdl.unlockTexture(.{self.texture});
    }

    pub fn putPixel(self: FrameBuffer, x: usize, y: usize, pixel: u32) void {
        if (self.pixels) |pixels| {
            pixels[x + y * self.width] = pixel;
        }
    }

    pub fn present(self: *FrameBuffer, renderer: *sdl.Renderer) !void {
        self.unlock();
        try sdl.renderCopy(.{ renderer, self.texture, null, null });
        sdl.renderPresent(.{renderer});
        try self.lock();
    }
};
