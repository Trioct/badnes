const std = @import("std");
const Allocator = std.mem.Allocator;

const bindings = @import("bindings.zig");
const c = bindings.c;
const Gl = bindings.Gl;

const Context = @import("context.zig").Context;

// currently using old style opengl for compatability
// not that I understand opengl

pub const BasicContext = struct {
    pixel_buffer: PixelBuffer,

    pub fn init(parent_context: *Context(false)) !BasicContext {
        try Gl.viewport(.{ 0, 0, 256 * 3, 240 * 3 });
        try Gl.enable(.{c.GL_TEXTURE_2D});

        try Gl.matrixMode(.{c.GL_PROJECTION});
        try Gl.loadIdentity();

        var self = BasicContext{
            .pixel_buffer = try PixelBuffer.init(parent_context.allocator, 256, 240),
        };

        self.pixel_buffer.scale = 3;

        return self;
    }

    pub fn deinit(self: BasicContext, allocator: *Allocator) void {
        self.pixel_buffer.deinit(allocator);
    }

    pub fn getGamePixelBuffer(self: *BasicContext) *PixelBuffer {
        return &self.pixel_buffer;
    }

    pub fn handleEvent(_: *BasicContext, event: c.SDL_Event) bool {
        switch (event.type) {
            c.SDL_KEYUP => switch (event.key.keysym.sym) {
                c.SDLK_q => return false,
                else => {},
            },
            c.SDL_QUIT => return false,
            else => {},
        }
        return true;
    }

    pub fn draw(self: BasicContext) !void {
        try Gl.pushClientAttrib(.{c.GL_CLIENT_ALL_ATTRIB_BITS});
        try Gl.pushMatrix();

        try Gl.enableClientState(.{c.GL_VERTEX_ARRAY});
        try Gl.enableClientState(.{c.GL_TEXTURE_COORD_ARRAY});

        try Gl.loadIdentity();
        try Gl.ortho(.{ 0, 256 * 3, 240 * 3, 0, 0, 1 });

        try self.pixel_buffer.drawRaw();

        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, 0 });

        try Gl.disableClientState(.{c.GL_VERTEX_ARRAY});
        try Gl.disableClientState(.{c.GL_TEXTURE_COORD_ARRAY});

        try Gl.popMatrix();
        try Gl.popClientAttrib();
    }
};

pub const PixelBuffer = struct {
    pixels: []u32 = null,
    width: usize,
    height: usize,
    scale: usize = 1,

    texture: c.GLuint,

    pub fn init(allocator: *Allocator, width: usize, height: usize) !PixelBuffer {
        var texture: c.GLuint = undefined;
        try Gl.genTextures(.{ 1, &texture });

        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, texture });

        try Gl.texParameteri(.{ c.GL_TEXTURE_2D, c.GL_TEXTURE_BASE_LEVEL, 0 });
        try Gl.texParameteri(.{ c.GL_TEXTURE_2D, c.GL_TEXTURE_MAX_LEVEL, 0 });
        try Gl.texParameteri(.{ c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST });
        try Gl.texParameteri(.{ c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST });

        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, 0 });

        return PixelBuffer{
            .pixels = try allocator.alloc(u32, width * height),
            .texture = texture,
            .width = width,
            .height = height,
        };
    }

    pub fn deinit(self: PixelBuffer, allocator: *Allocator) void {
        allocator.free(self.pixels);
        Gl.deleteTextures(.{ 1, &self.texture }) catch {};
    }

    pub fn putPixel(self: PixelBuffer, x: usize, y: usize, pixel: u32) void {
        self.pixels[x + y * self.width] = pixel;
    }

    /// Copies pixels into internal texture
    /// Does not call bindTexture, caller must take care of it
    pub fn copyTextureInternal(self: PixelBuffer) !void {
        try Gl.texImage2D(.{
            c.GL_TEXTURE_2D,
            0,
            c.GL_RGBA8,
            @intCast(c_int, self.width),
            @intCast(c_int, self.height),
            0,
            c.GL_RGBA,
            c.GL_UNSIGNED_INT_8_8_8_8,
            @ptrCast(*const c_void, self.pixels),
        });
    }

    /// Draws directly to the current opengl fbo (probably the screen)
    pub fn drawRaw(self: PixelBuffer) !void {
        const vertex_positions = [8]c_int{
            0,                                        0,
            @intCast(c_int, self.width * self.scale), 0,
            @intCast(c_int, self.width * self.scale), @intCast(c_int, self.height * self.scale),
            0,                                        @intCast(c_int, self.height * self.scale),
        };

        const tex_coords = [8]c_int{
            0, 0,
            1, 0,
            1, 1,
            0, 1,
        };

        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, self.texture });

        try self.copyTextureInternal();

        try Gl.vertexPointer(.{ 2, c.GL_INT, 0, &vertex_positions });
        try Gl.texCoordPointer(.{ 2, c.GL_INT, 0, &tex_coords });
        try Gl.drawArrays(.{ c.GL_QUADS, 0, 4 });

        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, 0 });
    }
};
