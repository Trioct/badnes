const std = @import("std");
const fs = std.fs;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
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
    quit: bool = false,

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

    fn isWindowAvailable(self: ImguiContext, name: []const u8) bool {
        if (self.windows.get(name)) |window| {
            return !window.open;
        }
        return true;
    }

    // TODO: very inefficient, not my focus right now
    fn makeWindowNameUnique(self: *ImguiContext, comptime name: []const u8) []const u8 {
        if (self.isWindowAvailable(name)) {
            const tagged = comptime if (std.mem.indexOf(u8, name, "##") != null) true else false;
            var new_name = comptime blk: {
                break :blk name ++ if (tagged) "00000" else "##00000";
            };
            const num_index = comptime if (tagged) name.len else name.len + 2;

            var i: u16 = 0;
            while (i < 65535) : (i += 1) {
                if (self.isWindowAvailable(new_name)) {
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
        const result = try self.windows.getOrPut(window.title);
        if (result.found_existing) {
            if (!result.value_ptr.open) {
                std.log.err("Overwriting window that's in use: {s}", .{window.title});
            }
            result.value_ptr.deinit(self.getParentContext().allocator);
        }
        result.value_ptr.* = window;
        std.log.debug("Added window: {s}", .{window.title});
    }

    fn getParentContext(self: *ImguiContext) *Context(true) {
        return @fieldParentPtr(Context(true), "extension_context", self);
    }

    pub fn getGamePixelBuffer(self: *ImguiContext) *PixelBuffer {
        return &self.game_pixel_buffer;
    }

    pub fn handleEvent(self: *ImguiContext, event: c.SDL_Event) bool {
        _ = Imgui.sdl2ProcessEvent(.{&event});
        switch (event.type) {
            c.SDL_QUIT => return false,
            else => {},
        }
        return !self.quit;
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
            _ = Imgui.menuItemPtr(.{ "Exit", null, &self.quit, true });
            Imgui.endMenu();
        }

        Imgui.endMainMenuBar();
    }

    fn openFileDialog(self: *ImguiContext, comptime reason: FileDialogReason) !void {
        const name = "Choose a file##" ++ @tagName(reason);
        if (!self.isWindowAvailable(name)) {
            return;
        }
        const file_dialog = Window.init(
            .{ .file_dialog = try FileDialog.init(self.getParentContext().allocator) },
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

    open: bool = true,

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
        if (!self.open) {
            return;
        }

        const c_title = @ptrCast([*]const u8, self.title);

        var new_open: bool = self.open;
        defer self.open = new_open;
        if (Imgui.begin(.{ c_title, &new_open, self.flags })) {
            if (new_open) {
                new_open = try self.impl.draw(context);
            } else {
                try self.impl.onClosed(context);
                std.log.debug("Closed window: {s}", .{self.title});
            }
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
            .file_dialog => |x| x.deinit(),
        }
    }

    fn draw(self: *WindowImpl, context: *ImguiContext) !bool {
        switch (self.*) {
            .game_window => |x| return x.draw(context.*),
            .file_dialog => |*x| return x.draw(context),
        }
    }

    fn onClosed(self: *WindowImpl, _: *ImguiContext) !void {
        switch (self.*) {
            .game_window => {},
            .file_dialog => {},
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

const StringBuilder = struct {
    buffer: ArrayList(u8),

    fn init(allocator: *Allocator, capacity: ?usize) !StringBuilder {
        if (capacity) |cap| {
            return StringBuilder{
                .buffer = try ArrayList(u8).initCapacity(allocator, cap),
            };
        } else {
            return StringBuilder{
                .buffer = ArrayList(u8).init(allocator),
            };
        }
    }

    fn deinit(self: StringBuilder) void {
        self.buffer.deinit();
    }

    fn toOwnedSlice(self: *StringBuilder) []u8 {
        return self.buffer.toOwnedSlice();
    }

    fn toOwnedSliceNull(self: *StringBuilder) ![:0]u8 {
        try self.buffer.append('\x00');
        const bytes = self.buffer.toOwnedSlice();
        return @ptrCast([*:0]u8, bytes)[0 .. bytes.len - 1 :0];
    }

    fn toRefBuffer(self: *StringBuilder, allocator: *Allocator) !RefBuffer(u8) {
        return RefBuffer(u8).from(allocator, self.toOwnedSlice());
    }

    fn clear(self: *StringBuilder) void {
        self.buffer.clearAndFree();
    }

    fn writer(self: *StringBuilder) std.io.Writer(*StringBuilder, Allocator.Error, StringBuilder.write) {
        return .{ .context = self };
    }

    fn write(self: *StringBuilder, bytes: []const u8) Allocator.Error!usize {
        try self.buffer.appendSlice(bytes);
        return bytes.len;
    }
};

fn RefBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: *Allocator,
        slice: []T,
        ref_count: *usize,

        fn init(allocator: *Allocator, size: usize) !Self {
            return Self.from(allocator, try allocator.alloc(T, size));
        }

        fn from(allocator: *Allocator, slice: []T) !Self {
            errdefer allocator.free(slice);
            var ref_count = try allocator.create(usize);
            ref_count.* = 1;
            return Self{
                .allocator = allocator,
                .slice = slice,
                .ref_count = ref_count,
            };
        }

        fn ref(self: Self) Self {
            self.ref_count.* += 1;
            return self;
        }

        fn unref(self: Self) void {
            self.ref_count.* -= 1;
            if (self.ref_count.* == 0) {
                self.allocator.free(self.slice);
                self.allocator.destroy(self.ref_count);
            }
        }
    };
}

// Janky api, fix if used in a contxt other than file dialog
const DirWalker = struct {
    allocator: *Allocator,

    dirs: ArrayList([:0]const u8),
    files: ArrayList(File),

    const File = struct {
        name: [:0]const u8,
        is_dir: bool,
    };

    fn init(allocator: *Allocator, path: []const u8, buffer: []u8) !DirWalker {
        var dir_strings = std.mem.split(u8, try fs.cwd().realpath(path, buffer), "/");

        var dirs = ArrayList([:0]const u8).init(allocator);
        errdefer dirs.deinit();

        var str = try StringBuilder.init(allocator, null);
        defer str.deinit();

        while (dir_strings.next()) |dir| {
            str.clear();
            try std.fmt.format(str.writer(), "{s}", .{dir});
            try dirs.append(try str.toOwnedSliceNull());
        }

        var self = DirWalker{
            .allocator = allocator,
            .dirs = dirs,
            .files = ArrayList(File).init(allocator),
        };

        try self.updateFiles();

        return self;
    }

    fn deinit(self: DirWalker) void {
        for (self.dirs.items) |dir| {
            self.allocator.free(dir);
        }
        self.dirs.deinit();

        for (self.files.items) |file| {
            self.allocator.free(file.name);
        }
        self.files.deinit();
    }

    fn getParentDirString(self: DirWalker) !StringBuilder {
        var str = try StringBuilder.init(self.allocator, null);

        for (self.dirs.items) |dir| {
            try std.fmt.format(str.writer(), "{s}/", .{dir});
        }

        return str;
    }

    fn selectParentDir(self: *DirWalker, index: usize) !void {
        var i: usize = self.dirs.items.len;
        while (i > index + 1) : (i -= 1) {
            const dir = self.dirs.pop();
            self.allocator.free(dir);
        }

        for (self.files.items) |file| {
            self.allocator.free(file.name);
        }
        self.files.clearAndFree();

        try self.updateFiles();
    }

    fn selectFile(self: *DirWalker, index: usize) !?[:0]const u8 {
        const selected_file = self.files.items[index];
        if (!selected_file.is_dir) {
            var parent_str = try self.getParentDirString();
            _ = try parent_str.write(selected_file.name);

            return try parent_str.toOwnedSliceNull();
        }

        for (self.files.items) |file, i| {
            if (i != index) {
                self.allocator.free(file.name);
            }
        }
        try self.dirs.append(selected_file.name);

        self.files.clearAndFree();
        try self.updateFiles();
        return null;
    }

    fn updateFiles(self: *DirWalker) !void {
        var str = try StringBuilder.init(self.allocator, null);
        defer str.deinit();

        const parent_path = try (try self.getParentDirString()).toOwnedSliceNull();
        defer self.allocator.free(parent_path);

        std.debug.print("{s}\n", .{parent_path});

        var dir = try fs.openDirAbsolute(parent_path, .{ .iterate = true });
        defer dir.close();

        var dir_iter = dir.iterate();
        while (try dir_iter.next()) |file| {
            str.clear();
            _ = try std.fmt.format(str.writer(), "{s}", .{file.name});
            try self.files.append(File{
                .name = try str.toOwnedSliceNull(),
                .is_dir = file.kind == .Directory,
            });
        }
    }
};

const FileDialog = struct {
    buffer: RefBuffer(u8),
    current_dir: DirWalker,

    fn init(allocator: *Allocator) !FileDialog {
        var buffer = try RefBuffer(u8).init(allocator, 1024);
        const current_dir = try DirWalker.init(allocator, ".", buffer.slice);

        return FileDialog{
            .buffer = buffer,
            .current_dir = current_dir,
        };
    }

    fn deinit(self: FileDialog) void {
        self.current_dir.deinit();
        self.buffer.unref();
    }

    fn draw(self: *FileDialog, context: *ImguiContext) !bool {
        {
            var dir_clicked: ?usize = null;
            for (self.current_dir.dirs.items) |dir, i| {
                const dir_name = if (i == 0) "/" else dir;
                if (Imgui.button(.{ dir_name, .{ .x = 0, .y = 0 } }) and dir_clicked == null) {
                    dir_clicked = i;
                }
                if (i != 0) {
                    Imgui.sameLine(.{ 0, 0 });
                    Imgui.text("/");
                }
                Imgui.sameLine(.{ 0, 0 });
            }
            Imgui.newLine();

            if (dir_clicked) |i| {
                try self.current_dir.selectParentDir(i);
            }
        }

        {
            var file_clicked: ?usize = null;
            for (self.current_dir.files.items) |file, i| {
                if (Imgui.button(.{ file.name, .{ .x = 0, .y = 0 } }) and file_clicked == null) {
                    file_clicked = i;
                }
            }
            if (file_clicked) |i| {
                if (try self.current_dir.selectFile(i)) |path| {
                    defer context.getParentContext().allocator.free(path);
                    context.console.clearState();
                    try context.console.loadRom(path);
                    return false;
                }
            }
        }

        return true;
    }
};
