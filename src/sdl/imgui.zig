const std = @import("std");
const Allocator = std.mem.Allocator;
const HashMap = std.StringHashMap;

const bindings = @import("bindings.zig");
const c = bindings.c;
const Sdl = bindings.Sdl;
const Gl = bindings.Gl;
const Imgui = bindings.Imgui;

const Console = @import("../console.zig").Console;

const Context = @import("context.zig").Context;
const PixelBuffer = @import("basic_video.zig").PixelBuffer;

const util = @import("imgui/util.zig");
const FileDialog = @import("imgui/file_dialog.zig").FileDialog;
const HexEditor = @import("imgui/hex_editor.zig").HexEditor;

pub const ImguiContext = struct {
    console: *Console(.{ .precision = .accurate, .method = .sdl }),
    windows: HashMap(Window),

    /// Do not manually set this, use the pause/unpause functions
    paused: bool = false,
    quit: bool = false,

    game_pixel_buffer: PixelBuffer,
    frame_timer: util.FrameTimer,

    // for my testing pleasure before input configuration
    temp_controller: ?*c.SDL_GameController,

    const FileDialogReason = enum {
        open_rom,
    };

    pub fn init(
        parent_context: *Context(.accurate, true),
    ) !ImguiContext {
        Sdl.setWindowSize(.{ parent_context.window, 1920, 1080 });
        Sdl.setWindowPosition(.{ parent_context.window, c.SDL_WINDOWPOS_CENTERED, c.SDL_WINDOWPOS_CENTERED });

        _ = try Imgui.createContext(.{null});
        try Imgui.sdl2InitForOpengl(.{ parent_context.window, parent_context.gl_context });
        try Imgui.opengl3Init(.{"#version 130"});

        Imgui.styleColorsDark(.{null});

        var self = ImguiContext{
            .console = &parent_context.console,
            .windows = HashMap(Window).init(parent_context.allocator),

            .game_pixel_buffer = try PixelBuffer.init(parent_context.allocator, 256, 240),
            .frame_timer = util.FrameTimer.init(null),

            .temp_controller = Sdl.gameControllerOpen(.{0}),
        };
        try self.pause();

        parent_context.console.controller.sdl_controller = self.temp_controller;

        self.game_pixel_buffer.scale = 3;

        errdefer self.deinit(parent_context.allocator);

        var game_window = Window.init(
            .{ .game_window = .{} },
            try parent_context.allocator.dupeZ(u8, "NES"),
            Imgui.windowFlagsAlwaysAutoResize,
        );
        game_window.closeable = false;
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

        Sdl.gameControllerClose(.{self.temp_controller});

        Imgui.opengl3Shutdown();
        Imgui.sdl2Shutdown();
    }

    fn isWindowAvailable(self: ImguiContext, name: []const u8) bool {
        if (self.windows.get(name)) |window| {
            return !window.open;
        }
        return true;
    }

    // TODO: very inefficient, not my focus right now
    fn makeWindowNameUnique(self: *ImguiContext, comptime name: [:0]const u8) ![:0]const u8 {
        if (self.isWindowAvailable(name)) {
            const tag_str = comptime if (std.mem.indexOf(u8, name, "##") != null) "" else "##";
            var str = util.StringBuilder.init(self.getParentContext().allocator);
            defer str.deinit();

            var i: u16 = 0;
            while (i < 65535) : (i += 1) {
                str.reset();
                _ = try std.fmt.format(str.writer(), "{s}{s}{d:0>5}", .{ name, tag_str, i });
                if (self.isWindowAvailable(str.buffer.items)) {
                    return try str.toOwnedSliceNull();
                }
            }
            @panic("Someone really went and made 65535 instances of the same window");
        } else {
            return name;
        }
    }

    fn addWindow(self: *ImguiContext, window: Window) !void {
        const result = try self.windows.getOrPut(window.title);
        if (result.found_existing) {
            if (result.value_ptr.open) {
                std.log.err("Overwriting window that's in use: {s}", .{window.title});
            }
            result.value_ptr.deinit(self.getParentContext().allocator);
        }
        result.value_ptr.* = window;
        std.log.debug("Added window: {s}", .{window.title});
    }

    pub fn getParentContext(self: *ImguiContext) *Context(.accurate, true) {
        return @fieldParentPtr(Context(.accurate, true), "extension_context", self);
    }

    pub fn getGamePixelBuffer(self: *ImguiContext) *PixelBuffer {
        return &self.game_pixel_buffer;
    }

    /// Pauses the console, sets vsync as the frame syncing method
    pub fn pause(self: *ImguiContext) !void {
        if (self.paused) {
            return;
        }
        self.paused = true;
        self.frame_timer.pause();
        self.getParentContext().audio_context.pause();
        try Sdl.glSetSwapInterval(.{1});
    }

    /// Unpauses the console, sync frames to the console (~60fps)
    pub fn unpause(self: *ImguiContext) !void {
        if (!self.paused) {
            return;
        }
        self.paused = false;
        self.frame_timer.unpause();
        self.getParentContext().audio_context.unpause();
        try Sdl.glSetSwapInterval(.{0});
    }

    pub fn togglePause(self: *ImguiContext) !void {
        if (self.paused) {
            return self.unpause();
        } else {
            return self.pause();
        }
    }

    pub fn isConsoleRunning(self: ImguiContext) bool {
        return !self.paused and self.console.cart.rom_loaded;
    }

    pub fn mainLoop(self: *ImguiContext) !void {
        var parent_context = self.getParentContext();
        var event: c.SDL_Event = undefined;

        parent_context.audio_context.unpause();

        var total_time: i128 = 0;
        var frames: usize = 0;
        mloop: while (!self.quit) {
            while (Sdl.pollEvent(.{&event}) == 1) {
                _ = Imgui.sdl2ProcessEvent(.{&event});
                switch (event.type) {
                    c.SDL_KEYDOWN => switch (event.key.keysym.sym) {
                        c.SDLK_SPACE => try self.togglePause(),
                        else => {},
                    },
                    c.SDL_QUIT => break :mloop,
                    else => {},
                }
            }

            if (!self.isConsoleRunning()) {
                try self.draw();
                continue;
            }

            if (self.console.ppu.present_frame) {
                frames += 1;
                self.console.ppu.present_frame = false;
                try self.draw();
                total_time += self.frame_timer.waitUntilNext(250 * std.time.ns_per_ms);

                if (total_time > std.time.ns_per_s) {
                    frames = 0;
                    total_time -= std.time.ns_per_s;
                }
            }

            // Batch run instructions/cycles to not get bogged down by Sdl.pollEvent
            if (self.console.cart.rom_loaded) {
                const cpu = &self.console.cpu;
                var i: usize = 0;
                switch (@import("build_options").precision) {
                    .fast => {
                        while (i < 2000) : (i += 1) {
                            cpu.runStep();
                        }
                    },
                    .accurate => {
                        while (i < 5000) : (i += 1) {
                            cpu.runStep();
                        }
                    },
                }
            }
        }
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

        Sdl.glSwapWindow(.{self.getParentContext().window});
    }

    fn drawMainMenu(self: *ImguiContext) !void {
        if (!Imgui.beginMainMenuBar()) {
            return;
        }
        defer Imgui.endMainMenuBar();

        if (Imgui.beginMenu(.{ "File", true })) {
            defer Imgui.endMenu();
            if (Imgui.menuItem(.{ "Open Rom", null, false, true })) {
                try self.openFileDialog(.open_rom);
            }
            _ = Imgui.menuItemPtr(.{ "Exit", null, &self.quit, true });
        }

        if (Imgui.beginMenu(.{ "Tools", true })) {
            defer Imgui.endMenu();
            if (Imgui.menuItem(.{ "Hex Editor", null, false, true })) {
                try self.addWindow(Window.init(
                    .{ .hex_editor = HexEditor.init() },
                    try self.makeWindowNameUnique("Hex Editor"),
                    Imgui.windowFlagsMenuBar,
                ));
            }
        }
    }

    fn openFileDialog(self: *ImguiContext, comptime reason: FileDialogReason) !void {
        const name = "Choose a file##" ++ @tagName(reason);
        if (!self.isWindowAvailable(name)) {
            return;
        }
        try self.addWindow(Window.init(
            .{ .file_dialog = try FileDialog.init(self.getParentContext().allocator) },
            try self.getParentContext().allocator.dupeZ(u8, name),
            Imgui.windowFlagsNone,
        ));
    }
};

const Window = struct {
    const Flags = @TypeOf(c.ImGuiWindowFlags_None);

    impl: WindowImpl,

    title: [:0]const u8,
    flags: Flags,

    closeable: bool = true,
    open: bool = true,

    fn init(impl: WindowImpl, title: [:0]const u8, flags: Flags) Window {
        return Window{
            .impl = impl,

            .title = title,
            .flags = flags,
        };
    }

    fn deinit(self: Window, allocator: *Allocator) void {
        self.impl.deinit(allocator);
        allocator.free(self.title);
    }

    fn draw(self: *Window, context: *ImguiContext) !void {
        if (!self.open) {
            return;
        }

        try self.impl.predraw(self, context);
        defer Imgui.end();
        if (self.closeable) {
            var new_open: bool = self.open;
            defer self.open = new_open;
            if (Imgui.begin(.{ self.title, &new_open, self.flags })) {
                if (new_open) {
                    new_open = try self.impl.draw(self, context);
                } else {
                    try self.impl.onClosed(context);
                    std.log.debug("Closed window: {s}", .{self.title});
                }
            }
        } else if (Imgui.begin(.{ self.title, null, self.flags })) {
            _ = try self.impl.draw(self, context);
        }
    }
};

const WindowImpl = union(enum) {
    game_window: GameWindow,
    file_dialog: FileDialog,
    hex_editor: HexEditor,

    fn deinit(self: WindowImpl, _: *Allocator) void {
        switch (self) {
            .game_window => {},
            .file_dialog => |x| x.deinit(),
            .hex_editor => {},
        }
    }

    fn predraw(self: *WindowImpl, _: *Window, _: *ImguiContext) !void {
        switch (self.*) {
            .game_window => {},
            .file_dialog => {},
            .hex_editor => |*x| try x.predraw(),
        }
    }

    fn draw(self: *WindowImpl, _: *Window, context: *ImguiContext) !bool {
        switch (self.*) {
            .game_window => |x| return x.draw(context.*),
            .file_dialog => |*x| return x.draw(context),
            .hex_editor => |*x| return x.draw(context),
        }
    }

    fn onClosed(self: *WindowImpl, _: *ImguiContext) !void {
        switch (self.*) {
            .game_window => {},
            .file_dialog => {},
            .hex_editor => {},
        }
    }
};

const GameWindow = struct {
    fn draw(_: GameWindow, context: ImguiContext) !bool {
        context.console.controller.read_input = Imgui.isWindowFocused(.{0});

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
