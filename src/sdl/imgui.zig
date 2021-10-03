const std = @import("std");
const Allocator = std.mem.Allocator;
const HashMap = std.StringHashMap;

const bindings = @import("bindings.zig");
const c = bindings.c;
const Sdl = bindings.Sdl;
const Gl = bindings.Gl;
const Imgui = bindings.Imgui;

const Context = @import("context.zig").Context;
const PixelBuffer = @import("basic_video.zig").PixelBuffer;

const Console = @import("../console.zig").Console;

pub const ImguiContext = struct {
    console: *Console(.{ .precision = .accurate, .method = .sdl }),
    windows: HashMap(Window),

    game_pixel_buffer: PixelBuffer,

    const FileDialogReason = enum {
        open_rom,
    };

    pub fn init(
        parent_context: *Context(true),
        console: *Console(.{ .precision = .accurate, .method = .sdl }),
    ) !ImguiContext {
        Sdl.setWindowSize(.{ parent_context.window, 1920, 1080 });
        Sdl.setWindowPosition(.{ parent_context.window, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED });

        _ = try Imgui.createContext(.{null});
        try Imgui.sdl2InitForOpengl(.{ parent_context.window, parent_context.gl_context });
        try Imgui.opengl3Init(.{"#version 130"});

        Imgui.styleColorsDark(.{null});

        var self = ImguiContext{
            .console = console,
            .windows = HashMap(Window).init(parent_context.allocator),

            .game_pixel_buffer = try PixelBuffer.init(parent_context.allocator, 256, 240),
        };

        self.game_pixel_buffer.scale = 3;

        errdefer self.deinit(parent_context.allocator);

        const game_window = Window.init(
            .{ .game_window = .{} },
            "NES",
            Imgui.windowFlagsAlwaysAutoResize,
        );
        try self.addWindow(game_window);

        return self;
    }

    pub fn deinit(self: *ImguiContext, allocator: *Allocator) void {
        var values = self.windows.valueIterator();
        while (values.next()) |window| {
            window.deinit(allocator);
        }
        self.windows.deinit();
        self.game_pixel_buffer.deinit(allocator);

        Imgui.opengl3Shutdown();
        Imgui.sdl2Shutdown();
    }

    fn getWindowAvailable(self: ImguiContext, name: []const u8) bool {
        if (self.windows.get(name)) |window| {
            return window.closed;
        }
        return true;
    }

    // TODO: very inefficient, not my focus right now
    fn makeWindowNameUnique(self: *ImguiContext, comptime name: []const u8) []const u8 {
        if (self.getWindowAvailable(name)) {
            const tagged = comptime if (std.mem.indexOf(u8, name, "##") != null) true else false;
            var new_name = comptime blk: {
                break :blk name ++ if (tagged) "00000" else "##00000";
            };
            const num_index = comptime if (tagged) name.len else name.len + 2;

            var i: u16 = 0;
            while (i < 65535) : (i += 1) {
                if (self.getWindowAvailable(new_name)) {
                    return new_name;
                }
                std.fmt.bufPrintIntToSlice(
                    new_name[num_index..],
                    i,
                    10,
                    .lower,
                    .{ .width = 5, .fill = '0' },
                );
            }
            @panic("Someone really went and made 65535 instances of the same window");
        } else {
            return name;
        }
    }

    fn addWindow(self: *ImguiContext, window: Window) !void {
        return self.windows.put(window.title, window);
    }

    fn getParentContext(self: *ImguiContext) *Context(true) {
        return @fieldParentPtr(Context(true), "extension_context", self);
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

        try self.drawMainMenu();

        var values = self.windows.valueIterator();
        while (values.next()) |window| {
            try window.draw(self);
        }

        try Gl.bindTexture(.{ c.GL_TEXTURE_2D, 0 });

        Gl.clearColor(.{ 0x00, 0x00, 0x00, 0xff });
        try Gl.clear(.{c.GL_COLOR_BUFFER_BIT});

        Imgui.render();
        Imgui.opengl3RenderDrawData(.{try Imgui.getDrawData()});
    }

    fn drawMainMenu(self: *ImguiContext) !void {
        if (!Imgui.beginMainMenuBar()) {
            return;
        }

        if (Imgui.beginMenu(.{ "File", true })) {
            if (Imgui.menuItem(.{ "Open Rom", null, false, true })) {
                try self.openFileDialog(.open_rom);
            }
            Imgui.endMenu();
        }

        Imgui.endMainMenuBar();
    }

    fn openFileDialog(self: *ImguiContext, comptime reason: FileDialogReason) !void {
        const name = "Choose a file##" ++ @tagName(reason);
        if (!self.getWindowAvailable(name)) {
            return;
        }
        const file_dialog = Window.init(
            .{ .file_dialog = .{} },
            name,
            Imgui.windowFlagsNone,
        );
        try self.addWindow(file_dialog);
    }
};

const Window = struct {
    const Flags = @TypeOf(c.ImGuiWindowFlags_None);

    impl: WindowImpl,

    title: []const u8,
    flags: Flags,

    closed: bool = false,

    fn init(impl: WindowImpl, title: []const u8, flags: Flags) Window {
        return Window{
            .impl = impl,

            .title = title,
            .flags = flags,
        };
    }

    fn deinit(self: Window, allocator: *Allocator) void {
        self.impl.deinit(allocator);
    }

    fn draw(self: *Window, context: *ImguiContext) !void {
        if (self.closed) {
            return;
        }
        const c_title = @ptrCast([*]const u8, self.title);
        if (Imgui.begin(.{ c_title, null, self.flags })) {
            self.closed = !(try self.impl.draw(context));
        }
        Imgui.end();
    }
};

const WindowImpl = union(enum) {
    game_window: GameWindow,
    file_dialog: FileDialog,

    fn deinit(self: WindowImpl, allocator: *Allocator) void {
        _ = allocator;
        switch (self) {
            .game_window => {},
            .file_dialog => {},
        }
    }

    fn draw(self: WindowImpl, context: *ImguiContext) !bool {
        switch (self) {
            .game_window => |x| return x.draw(context.*),
            .file_dialog => |x| return x.draw(context),
        }
    }
};

const GameWindow = struct {
    fn draw(_: GameWindow, context: ImguiContext) !bool {
        const pixel_buffer = &context.game_pixel_buffer;

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

        return true;
    }
};

const FileDialog = struct {
    fn draw(_: FileDialog, context: *ImguiContext) !bool {
        if (Imgui.button(.{ "Play golf lol", .{ .x = 0, .y = 0 } })) {
            context.console.clearState();
            try context.console.loadRom(
                "roms/no-redist/NES Open Tournament Golf (USA).nes",
            );
            return false;
        }
        return true;
    }
};
