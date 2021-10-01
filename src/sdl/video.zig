const std = @import("std");
const time = std.time;
const Allocator = std.mem.Allocator;

const bindings = @import("bindings.zig");
const c = bindings.c;
const Sdl = bindings.Sdl;
const Gl = bindings.Gl;

// currently using old style opengl for compatability
// not that I understand opengl

pub const Context = struct {
    window: *Sdl.Window,
    gl_context: Sdl.GLContext,

    frame_buffer: FrameBuffer,

    last_frame_time: i128,
    next_frame_time: i128,

    pub fn init(allocator: *Allocator, title: [:0]const u8) !Context {
        const width = 256 * 3;
        const height = 240 * 3;

        const window = try Sdl.createWindow(.{
            title,
            c.SDL_WINDOWPOS_CENTERED,
            c.SDL_WINDOWPOS_CENTERED,
            width,
            height,
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

        try Gl.viewport(.{ 0, 0, width, height });
        try Gl.enable(.{c.GL_TEXTURE_2D});

        try Gl.matrixMode(.{c.GL_PROJECTION});
        try Gl.loadIdentity();

        const now = time.nanoTimestamp();

        return Context{
            .window = window,
            .gl_context = gl_context,

            .frame_buffer = try FrameBuffer.init(allocator, 256, 240, 3),

            .last_frame_time = now,
            .next_frame_time = now,
        };
    }

    pub fn deinit(self: Context, allocator: *Allocator) void {
        self.frame_buffer.deinit(allocator);

        Sdl.glDeleteContext(.{self.gl_context});
        Sdl.destroyWindow(.{self.window});
    }

    pub const DrawOptions = struct {
        timing: enum {
            untimed,
            timed,
        },
        // ~1/60
        frametime: f32 = (4 * (261 * 341 + 340.5)) / 21477272.0,
    };

    fn drawFrameBuffers(self: *Context) !void {
        try Gl.pushClientAttrib(.{c.GL_CLIENT_ALL_ATTRIB_BITS});
        try Gl.pushMatrix();

        try Gl.enableClientState(.{c.GL_VERTEX_ARRAY});
        try Gl.enableClientState(.{c.GL_TEXTURE_COORD_ARRAY});

        var width: c_int = undefined;
        var height: c_int = undefined;
        Sdl.getWindowSize(.{ self.window, &width, &height });

        try Gl.loadIdentity();
        try Gl.ortho(.{ 0, @intToFloat(f64, width), @intToFloat(f64, height), 0, 0, 1 });

        try self.frame_buffer.draw(0, 0);

        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, 0 });

        try Gl.disableClientState(.{c.GL_VERTEX_ARRAY});
        try Gl.disableClientState(.{c.GL_TEXTURE_COORD_ARRAY});

        try Gl.popMatrix();
        try Gl.popClientAttrib();
    }

    pub fn drawFrame(self: *Context, draw_options: DrawOptions) !i128 {
        try self.drawFrameBuffers();
        Sdl.glSwapWindow(.{self.window});

        const frame_ns = @floatToInt(i128, time.ns_per_s * draw_options.frametime);
        const now = time.nanoTimestamp();
        const to_sleep = self.next_frame_time - now;
        var passed = now - self.last_frame_time;

        switch (draw_options.timing) {
            .untimed => {},
            .timed => if (to_sleep > 0) {
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
    pixels: []u32 = null,
    width: u31,
    height: u31,
    scale: u31,

    texture: c.GLuint,

    fn init(allocator: *Allocator, width: u31, height: u31, scale: u31) !FrameBuffer {
        var texture: c.GLuint = undefined;
        try Gl.genTextures(.{ 1, &texture });

        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, texture });

        try Gl.texParameteri(.{ c.GL_TEXTURE_2D, c.GL_TEXTURE_BASE_LEVEL, 0 });
        try Gl.texParameteri(.{ c.GL_TEXTURE_2D, c.GL_TEXTURE_MAX_LEVEL, 0 });
        try Gl.texParameteri(.{ c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST });
        try Gl.texParameteri(.{ c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST });

        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, 0 });

        return FrameBuffer{
            .pixels = try allocator.alloc(u32, width * height),
            .texture = texture,
            .width = width,
            .height = height,
            .scale = scale,
        };
    }

    fn deinit(self: FrameBuffer, allocator: *Allocator) void {
        allocator.free(self.pixels);
        Gl.deleteTextures(.{ 1, &self.texture }) catch {};
    }

    pub fn putPixel(self: FrameBuffer, x: usize, y: usize, pixel: u32) void {
        self.pixels[x + y * self.width] = pixel;
    }

    pub fn draw(self: *FrameBuffer, x: u31, y: u31) !void {
        const vertex_positions = [8]c_int{
            x,                           y,
            x + self.width * self.scale, y,
            x + self.width * self.scale, y + self.height * self.scale,
            x,                           y + self.height * self.scale,
        };

        const tex_coords = [8]c_int{
            0, 0,
            1, 0,
            1, 1,
            0, 1,
        };

        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, self.texture });

        try Gl.texImage2D(.{
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA8,
            self.width,
            self.height,
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_INT_8_8_8_8,
            @ptrCast(*const c_void, self.pixels),
        });

        try Gl.vertexPointer(.{ 2, c.GL_INT, 0, &vertex_positions });
        try Gl.texCoordPointer(.{ 2, c.GL_INT, 0, &tex_coords });
        try Gl.drawArrays(.{ c.GL_QUADS, 0, 4 });

        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, 0 });
    }
};
