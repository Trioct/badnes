const std = @import("std");
const time = std.time;
const Allocator = std.mem.Allocator;

const bindings = @import("bindings.zig");
const c = bindings.c;
const Sdl = bindings.Sdl;
const Gl = bindings.Gl;

const BasicContext = @import("basic_video.zig").BasicContext;
const PixelBuffer = @import("basic_video.zig").PixelBuffer;

pub const Context = struct {
    allocator: Allocator,
    window: *Sdl.Window,
    gl_context: Sdl.GLContext,
    draw_context: BasicContext,

    last_frame_time: i128,
    next_frame_time: i128,

    pub const DrawOptions = struct {
        timing: enum {
            untimed,
            timed,
        },
        // ~1/60
        frametime: f32 = (4 * (261 * 341 + 340.5)) / 21477272.0,
    };

    pub fn init(allocator: Allocator, title: [:0]const u8) !Context {
        const window = try Sdl.createWindow(.{
            title,
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            256 * 3,
            240 * 3,
            c.SDL_WINDOW_OPENGL,
        });
        errdefer Sdl.destroyWindow(.{window});

        try Sdl.glSetAttribute(.{ c.SDL_GL_CONTEXT_MAJOR_VERSION, 3 });
        try Sdl.glSetAttribute(.{ c.SDL_GL_CONTEXT_MINOR_VERSION, 0 });
        try Sdl.glSetAttribute(.{ c.SDL_GL_CONTEXT_FLAGS, 0 });
        try Sdl.glSetAttribute(.{ c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE });

        try Sdl.glSetAttribute(.{ c.SDL_GL_DOUBLEBUFFER, 1 });
        try Sdl.glSetAttribute(.{ c.SDL_GL_DEPTH_SIZE, 0 });

        const gl_context = try Sdl.glCreateContext(.{window});
        errdefer Sdl.glDeleteContext(.{gl_context});
        try Sdl.glMakeCurrent(.{ window, gl_context });
        try Sdl.glSetSwapInterval(.{0});

        var self = Context{
            .allocator = allocator,
            .window = window,
            .gl_context = gl_context,
            .draw_context = undefined,

            .last_frame_time = undefined,
            .next_frame_time = undefined,
        };

        const draw_context = try BasicContext.init(self);
        const now = time.nanoTimestamp();

        self.draw_context = draw_context;
        self.last_frame_time = now;
        self.next_frame_time = now;

        return self;
    }

    pub fn deinit(self: *Context, allocator: Allocator) void {
        self.draw_context.deinit(allocator);

        Sdl.glDeleteContext(.{self.gl_context});
        Sdl.destroyWindow(.{self.window});
    }

    pub inline fn getGamePixelBuffer(self: *Context) *PixelBuffer {
        return self.draw_context.getGamePixelBuffer();
    }

    pub inline fn handleEvent(self: *Context, event: c.SDL_Event) bool {
        return self.draw_context.handleEvent(event);
    }

    pub fn draw(self: *Context, draw_options: DrawOptions) !i128 {
        try self.draw_context.draw();
        Sdl.glSwapWindow(.{self.window});

        const frame_ns: i128 = @intFromFloat(time.ns_per_s * draw_options.frametime);
        const now = time.nanoTimestamp();
        const to_sleep = self.next_frame_time - now;
        var passed = now - self.last_frame_time;

        switch (draw_options.timing) {
            .untimed => {},
            .timed => if (to_sleep > 0) {
                time.sleep(@intCast(to_sleep));
                passed += to_sleep;
            },
        }

        self.next_frame_time += frame_ns;
        self.last_frame_time += passed;

        return passed;
    }
};
