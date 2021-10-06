const std = @import("std");
const Allocator = std.mem.Allocator;

const Imgui = @import("../bindings.zig").Imgui;
const ImguiContext = @import("../imgui.zig").ImguiContext;

const util = @import("util.zig");

pub const HexEditor = struct {
    memory: Memory = .cpu_ram,
    value_strs: util.StringBuilder,

    const Memory = enum {
        cpu_ram,
    };

    pub fn init(allocator: *Allocator) HexEditor {
        return HexEditor{
            .value_strs = util.StringBuilder.init(allocator),
        };
    }

    pub fn deinit(self: HexEditor) void {
        self.value_strs.deinit();
    }

    pub fn draw(self: *HexEditor, context: ImguiContext) !bool {
        // TODO: add update rate limiter
        self.updateValues(context) catch |err| {
            std.log.err("{}", .{err});
            return false;
        };

        const value_strs = self.value_strs.buffer.items;

        defer Imgui.endTable();
        if (Imgui.beginTable(.{ "Memory Table", 16, 0, .{ .x = 0, .y = 0 }, 0 })) {
            var i: usize = 0;
            while (i < value_strs.len) : (i += 3) {
                if (Imgui.tableNextColumn()) {
                    Imgui.text(value_strs[i .. i + 2 :0]);
                    // const buf = vals[i .. i + 2 :0];
                    // _ = c.igInputText("", buf, 2, 0, null, null);
                }
            }
        }

        return true;
    }

    fn updateValues(self: *HexEditor, context: ImguiContext) !void {
        const slice = switch (self.memory) {
            .cpu_ram => context.console.cpu.mem.ram,
        };

        self.value_strs.reset();
        var writer = self.value_strs.writer();
        for (slice) |byte| {
            try std.fmt.format(writer, "{x:0>2}\x00", .{byte});
        }
    }
};
