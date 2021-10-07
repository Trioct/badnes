const std = @import("std");
const Allocator = std.mem.Allocator;

const build_options = @import("build_options");

const bindings = @import("bindings.zig");
const c = bindings.c;
const Sdl = bindings.Sdl;
const Gl = bindings.Gl;

const Console = @import("../console.zig").Console;
const Precision = @import("../console.zig").Precision;

const audio = @import("audio.zig");
const BasicContext = @import("basic_video.zig").BasicContext;
const PixelBuffer = @import("basic_video.zig").PixelBuffer;
const ImguiContext = @import("imgui.zig").ImguiContext;

pub fn runImpl() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();

    var allocator = &gpa.allocator;

    try Sdl.init(.{c.SDL_INIT_VIDEO | c.SDL_INIT_AUDIO | c.SDL_INIT_EVENTS});
    defer Sdl.quit();

    var context = Context(
        comptime std.meta.stringToEnum(Precision, @tagName(build_options.precision)).?,
        build_options.imgui,
    ).pin();
    try context.init(allocator);
    defer context.deinit();

    var args_iter = std.process.args();
    _ = args_iter.skip();

    if (args_iter.next(allocator)) |arg| {
        const path = try arg;
        defer allocator.free(path);
        try context.console.loadRom(path);
    }

    try context.mainLoop();
}

pub fn Context(comptime precision: Precision, comptime using_imgui: bool) type {
    const ExtensionContext = if (using_imgui) ImguiContext else BasicContext(precision);
    return struct {
        const Self = @This();

        allocator: *Allocator,

        window: *Sdl.Window,
        gl_context: Sdl.GLContext,
        audio_context: audio.Context,
        extension_context: ExtensionContext,

        console: Console(.{ .precision = precision, .method = .sdl }),

        pub const DrawOptions = struct {
            timing: enum {
                untimed,
                timed,
            },
            // ~1/60
            frametime: f32 = (4 * (261 * 341 + 340.5)) / 21477272.0,
        };

        pub fn pin() Self {
            return Self{
                .allocator = undefined,

                .console = undefined,
                .window = undefined,
                .gl_context = undefined,
                .audio_context = undefined,
                .extension_context = undefined,
            };
        }

        pub fn init(self: *Self, allocator: *Allocator) !void {
            self.allocator = allocator;
            self.window = try Sdl.createWindow(.{
                "Badnes",
                c.SDL_WINDOWPOS_CENTERED,
                c.SDL_WINDOWPOS_CENTERED,
                256 * 3,
                240 * 3,
                c.SDL_WINDOW_OPENGL,
            });

            try Sdl.glSetAttribute(.{ c.SDL_GL_CONTEXT_MAJOR_VERSION, 3 });
            try Sdl.glSetAttribute(.{ c.SDL_GL_CONTEXT_MINOR_VERSION, 0 });
            try Sdl.glSetAttribute(.{ c.SDL_GL_CONTEXT_FLAGS, 0 });
            try Sdl.glSetAttribute(.{ c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE });

            try Sdl.glSetAttribute(.{ c.SDL_GL_DOUBLEBUFFER, 1 });
            try Sdl.glSetAttribute(.{ c.SDL_GL_DEPTH_SIZE, 0 });

            self.gl_context = try Sdl.glCreateContext(.{self.window});
            try Sdl.glMakeCurrent(.{ self.window, self.gl_context });
            try Sdl.glSetSwapInterval(.{0});

            self.audio_context = try audio.Context.alloc(allocator);
            try self.audio_context.init();
            self.console.init(allocator, self.getGamePixelBuffer(), &self.audio_context);

            self.extension_context = try ExtensionContext.init(self);
        }

        pub fn deinit(self: *Self) void {
            self.extension_context.deinit(self.allocator);
            self.audio_context.deinit(self.allocator);
            self.console.deinit();

            Sdl.glDeleteContext(.{self.gl_context});
            Sdl.destroyWindow(.{self.window});
        }

        pub inline fn getGamePixelBuffer(self: *Self) *PixelBuffer {
            return self.extension_context.getGamePixelBuffer();
        }

        pub inline fn mainLoop(self: *Self) !void {
            return self.extension_context.mainLoop();
        }
    };
}
