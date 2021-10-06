const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Imgui = @import("../bindings.zig").Imgui;
const ImguiContext = @import("../imgui.zig").ImguiContext;

const util = @import("util.zig");

pub const FileDialog = struct {
    buffer: util.RefBuffer(u8),
    current_dir: DirWalker,

    pub fn init(allocator: *Allocator) !FileDialog {
        var buffer = try util.RefBuffer(u8).init(allocator, 1024);
        const current_dir = try DirWalker.init(allocator, ".", buffer.slice);

        return FileDialog{
            .buffer = buffer,
            .current_dir = current_dir,
        };
    }

    pub fn deinit(self: FileDialog) void {
        self.current_dir.deinit();
        self.buffer.unref();
    }

    pub fn draw(self: *FileDialog, context: *ImguiContext) !bool {
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
            defer Imgui.endChild();
            if (Imgui.beginChild(.{ "File List", .{ .x = 0, .y = 0 }, false, Imgui.windowFlagsNone })) {
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
                        context.console.loadRom(path) catch |err| {
                            std.log.err("{}", .{err});
                        };
                        return false;
                    }
                }
            }
        }

        return true;
    }
};

// Janky api, fix if used in a contxt other than file dialog
const DirWalker = struct {
    allocator: *Allocator,

    dirs: ArrayList([:0]const u8),
    files: ArrayList(File),

    const File = struct {
        name: [:0]const u8,
        kind: std.fs.Dir.Entry.Kind,
    };

    fn init(allocator: *Allocator, path: []const u8, buffer: []u8) !DirWalker {
        var dir_strings = std.mem.split(u8, try std.fs.cwd().realpath(path, buffer), "/");

        var dirs = ArrayList([:0]const u8).init(allocator);
        errdefer dirs.deinit();

        var str = try util.StringBuilder.init(allocator, null);
        defer str.deinit();

        while (dir_strings.next()) |dir| {
            str.reset();
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

    fn getParentDirString(self: DirWalker) !util.StringBuilder {
        var str = try util.StringBuilder.init(self.allocator, null);

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

        self.updateFiles() catch |err| {
            std.log.err("{}: Failed to select file", .{err});
        };
    }

    fn selectFile(self: *DirWalker, index: usize) !?[:0]const u8 {
        const selected_file = self.files.items[index];

        switch (selected_file.kind) {
            .File => {
                var parent_str = try self.getParentDirString();
                defer parent_str.deinit();

                _ = try parent_str.write(selected_file.name);
                return try parent_str.toOwnedSliceNull();
            },
            .Directory => {
                for (self.files.items) |file, i| {
                    if (i != index) {
                        self.allocator.free(file.name);
                    }
                }
                try self.dirs.append(selected_file.name);

                self.files.clearAndFree();
                self.updateFiles() catch |err| {
                    std.log.err("{}", .{err});
                };
                return null;
            },
            else => return null,
        }
    }

    fn updateFiles(self: *DirWalker) !void {
        var str = try util.StringBuilder.init(self.allocator, null);
        defer str.deinit();

        const parent_path = try (try self.getParentDirString()).toOwnedSliceNull();
        defer self.allocator.free(parent_path);

        var dir = try std.fs.openDirAbsolute(parent_path, .{ .iterate = true });
        defer dir.close();

        var dir_iter = dir.iterate();
        while (try dir_iter.next()) |file| {
            str.reset();
            _ = try std.fmt.format(str.writer(), "{s}", .{file.name});
            try self.files.append(File{
                .name = try str.toOwnedSliceNull(),
                .kind = file.kind,
            });
        }
    }
};
