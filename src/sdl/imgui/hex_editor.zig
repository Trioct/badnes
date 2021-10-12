// With help from https://github.com/ocornut/imgui_club

const std = @import("std");
const Allocator = std.mem.Allocator;

const bindings = @import("../bindings.zig");
const c = bindings.c;
const Imgui = bindings.Imgui;

const ImguiContext = @import("../imgui.zig").ImguiContext;
const util = @import("util.zig");

pub const HexEditor = struct {
    address_space: AddressSpace = .ppu,
    value_strs: util.StringBuilder,

    layout: Layout = Layout{},

    cell_selection: ?CellSelection = null,

    const CellSelection = struct {
        index: usize,
        editing: bool,
        just_selected: bool = true,
    };

    const AddressSpace = enum {
        cpu,
        ppu,
    };

    pub fn init(allocator: *Allocator) HexEditor {
        return HexEditor{
            .value_strs = util.StringBuilder.init(allocator),
        };
    }

    pub fn deinit(self: HexEditor) void {
        self.value_strs.deinit();
    }

    pub fn draw(self: *HexEditor, context: *ImguiContext) !bool {
        // TODO: add update rate limiter
        if (context.isConsoleRunning()) {
            self.updateValues(context.*) catch |err| {
                std.log.err("{}", .{err});
                return false;
            };
        }

        const value_strs = self.value_strs.buffer.items;
        if (value_strs.len == 0) {
            return true;
        }

        const draw_list = try Imgui.getWindowDrawList();

        const digit_size = blk: {
            var temp: Imgui.Vec2 = undefined;
            Imgui.calcTextSize(.{ &temp, "0", null, false, -1 });
            break :blk temp;
        };

        // TODO: make/search for issue
        const this_avoids_a_miscompile = .{ .x = digit_size.x, .y = 0 };
        Imgui.pushStyleVarVec2(.{ c.ImGuiStyleVar_FramePadding, .{ .x = 0, .y = 0 } });
        Imgui.pushStyleVarVec2(.{ c.ImGuiStyleVar_ItemSpacing, this_avoids_a_miscompile });
        defer Imgui.popStyleVar(.{2});

        if (Imgui.isMouseClicked(.{ 0, false })) {
            self.cell_selection = null;
        }

        const chunked_values = @ptrCast([*]([2:0]u8), value_strs)[0..@divExact(value_strs.len, 3)];
        for (chunked_values) |*str, i| {
            const is_selected = if (self.cell_selection != null) i == self.cell_selection.?.index else false;

            if (is_selected) {
                const cursor_pos = blk: {
                    var temp: Imgui.Vec2 = undefined;
                    Imgui.getCursorScreenPos(.{&temp});
                    break :blk temp;
                };

                // TODO: using the wrapped function causes a compiler bug
                // https://github.com/ziglang/zig/issues/6446
                //Imgui.addRectFilled(.{
                c.ImDrawList_AddRectFilled(
                    draw_list,
                    cursor_pos,
                    .{ .x = cursor_pos.x + digit_size.x * 2, .y = cursor_pos.y + digit_size.y },
                    0xffd05050,
                    0,
                    0,
                );
            }

            if (is_selected and self.cell_selection != null and self.cell_selection.?.editing) {
                const selection = &self.cell_selection.?;
                Imgui.setNextItemWidth(.{digit_size.x * 2});

                const was_just_selected = selection.just_selected;
                // TODO: why does the mouse getting released unfocus the inputText?
                if (selection.just_selected or (Imgui.isWindowFocused(.{0}) and c.igIsMouseReleased(0))) {
                    c.igSetKeyboardFocusHere(0);
                    selection.just_selected = false;
                }

                Imgui.pushIdInt(.{@intCast(c_int, i)});
                defer Imgui.popId();

                // TODO: callback
                if (Imgui.inputText(.{
                    "##hex input",
                    str,
                    @sizeOf(@TypeOf(str)), // wants raw size
                    Imgui.inputTextFlagsCharsHexadecimal |
                        Imgui.inputTextFlagsEnterReturnsTrue |
                        Imgui.inputTextFlagsNoHorizontalScroll |
                        Imgui.inputTextFlagsAutoSelectAll |
                        Imgui.inputTextFlagsAlwaysOverwrite,
                    null,
                    null,
                })) {
                    if (str[2] != '\x00') {
                        // TODO: search for issue
                        std.log.warn("imgui broke our null terminator", .{});
                        str[2] = '\x00';
                    }
                    if (!was_just_selected and str[0] != '\x00' and str[1] != '\x00') {
                        try self.setMemoryValue(context.*, i, str[0..2]);
                        selection.index +|= 1;
                        selection.just_selected = true;
                    }
                }
            } else {
                Imgui.text(str[0..2 :0]);
            }

            if (Imgui.isItemClicked(.{0})) {
                self.cell_selection = CellSelection{
                    .index = i,
                    .editing = true,
                };
            }

            if (i & 0xf != 0xf) {
                const spacing = if (i & 0x7 == 0x7) digit_size.x * 2 else -1;
                Imgui.sameLine(.{ 0, spacing });
            }
        }

        return true;
    }

    fn setMemoryValue(self: HexEditor, context: ImguiContext, addr: usize, str: []const u8) !void {
        std.debug.assert(str.len == 2);

        const val = try std.fmt.parseInt(u8, str, 16);

        switch (self.address_space) {
            .cpu => context.console.cpu.mem.sneak(@truncate(u16, addr), val),
            .ppu => context.console.ppu.mem.sneak(@truncate(u14, addr), val),
        }
    }

    fn updateValues(self: *HexEditor, context: ImguiContext) !void {
        const cpu = &context.console.cpu;
        const ppu = &context.console.ppu;
        const max_addr: usize = switch (self.address_space) {
            .cpu => 0xffff,
            .ppu => 0x3fff,
        };

        self.value_strs.reset();
        var writer = self.value_strs.writer();

        var i: usize = 0;
        while (i <= max_addr) : (i += 1) {
            const byte = switch (self.address_space) {
                .cpu => cpu.mem.peek(@truncate(u16, i)),
                .ppu => ppu.mem.peek(@truncate(u14, i)),
            };
            try std.fmt.format(writer, "{x:0>2}\x00", .{byte});
        }
    }
};

const Layout = struct {};
