const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const bindings = @import("bindings.zig");
const c = bindings.c;
const Sdl = bindings.Sdl;
const Gl = bindings.Gl;
const Imgui = bindings.Imgui;

const Context = @import("context.zig").Context;
const PixelBuffer = @import("basic_video.zig").PixelBuffer;

pub const ImguiContext = struct {
    parent_context: *Context(true),
    windows: ArrayList(Window),

    game_pixel_buffer: PixelBuffer,

    pub fn init(allocator: *Allocator, parent_context: *Context(true)) !ImguiContext {
        Sdl.setWindowSize(.{ parent_context.window, 1920, 1080 });

        _ = try Imgui.createContext(.{null});
        try Imgui.sdl2InitForOpengl(.{ parent_context.window, parent_context.gl_context });
        try Imgui.opengl3Init(.{"#version 130"});

        Imgui.styleColorsDark(.{null});

        var self = ImguiContext{
            .parent_context = parent_context,
            .windows = ArrayList(Window).init(allocator),

            .game_pixel_buffer = try PixelBuffer.init(allocator, 256, 240),
        };

        self.game_pixel_buffer.scale = 3;

        errdefer self.deinit(allocator);

        var game_window = try self.windows.addOne();
        game_window.* = Window.init(allocator, "NES");

        try game_window.widgets.append(Widget{ .game_pixel_buffer = .{} });

        return self;
    }

    pub fn deinit(self: ImguiContext, allocator: *Allocator) void {
        for (self.windows.items) |window| {
            window.deinit(allocator);
        }
        self.windows.deinit();
        self.game_pixel_buffer.deinit(allocator);

        Imgui.opengl3Shutdown();
        Imgui.sdl2Shutdown();
    }

    pub fn getGamePixelBuffer(self: *ImguiContext) *PixelBuffer {
        return &self.game_pixel_buffer;
    }

    pub fn handleEvent(_: *ImguiContext, event: c.SDL_Event) bool {
        _ = Imgui.sdl2ProcessEvent(.{&event});
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

    pub fn draw(self: *ImguiContext) !void {
        Imgui.opengl3NewFrame();
        Imgui.sdl2NewFrame();
        Imgui.newFrame();

        for (self.windows.items) |window| {
            try window.draw(self.*);
        }

        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, 0 });

        Gl.clearColor(.{ 0x00, 0x00, 0x00, 0xff });
        try Gl.clear(.{c.GL_COLOR_BUFFER_BIT});

        Imgui.render();
        Imgui.opengl3RenderDrawData(.{try Imgui.getDrawData()});
    }
};

const Window = struct {
    title: []const u8,
    widgets: ArrayList(Widget),

    fn init(allocator: *Allocator, title: []const u8) Window {
        return Window{
            .title = title,
            .widgets = ArrayList(Widget).init(allocator),
        };
    }

    fn deinit(self: Window, allocator: *Allocator) void {
        for (self.widgets.items) |widget| {
            widget.deinit(allocator);
        }
        self.widgets.deinit();
    }

    fn draw(self: Window, context: ImguiContext) !void {
        try Imgui.begin(.{ @ptrCast([*]const u8, self.title), null, 0 });
        for (self.widgets.items) |widget| {
            try widget.draw(context);
        }
        Imgui.end();
    }
};

// TODO: consider vtable implementation?
const Widget = union(enum) {
    game_pixel_buffer: GamePixelBuffer,
    pixel_buffer: PixelBuffer,

    const GamePixelBuffer = struct {
        fn draw(_: GamePixelBuffer, context: ImguiContext) !void {
            return Widget.drawPixelBuffer(context.game_pixel_buffer);
        }
    };

    fn deinit(self: Widget, allocator: *Allocator) void {
        switch (self) {
            .game_pixel_buffer => {},
            .pixel_buffer => |x| x.deinit(allocator),
        }
    }

    fn draw(self: Widget, context: ImguiContext) !void {
        switch (self) {
            .game_pixel_buffer => |x| try x.draw(context),
            .pixel_buffer => |x| try x.drawRaw(),
        }
    }

    fn drawPixelBuffer(pixel_buffer: PixelBuffer) !void {
        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, pixel_buffer.texture });
        try pixel_buffer.copyTextureInternal();
        const texture_ptr = @intToPtr(*c_void, pixel_buffer.texture);

        const f_width = @intToFloat(f32, pixel_buffer.width * pixel_buffer.scale);
        const f_height = @intToFloat(f32, pixel_buffer.height * pixel_buffer.scale);

        const size = .{ .x = f_width, .y = f_height };

        Imgui.image(.{
            texture_ptr,
            size,
            .{ .x = 0, .y = 0 },
            .{ .x = 1, .y = 1 },
            .{ .x = 1, .y = 1, .z = 1, .w = 1 },
            .{ .x = 0, .y = 0, .z = 0, .w = 0 },
        });
    }
};
