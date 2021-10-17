// With help from https://github.com/ocornut/imgui_club

const std = @import("std");
const Allocator = std.mem.Allocator;

const bindings = @import("../bindings.zig");
const c = bindings.c;
const Imgui = bindings.Imgui;

const ImguiContext = @import("../imgui.zig").ImguiContext;
const util = @import("util.zig");

pub const HexEditor = struct {
    layout: Layout = Layout{
        .address_digits = 4,
        .extra_spacing_every_8 = 1,
        .bytes_per_line = 16,

        .char_size = .{
            .x = 0,
            .y = 0,
        },
        .window_width = 0,
    },

    address_space: AddressSpace = .cpu,
    cell_selection: ?CellSelection = null,

    const Layout = struct {
        address_digits: usize,
        extra_spacing_every_8: usize,
        bytes_per_line: usize,

        char_size: Imgui.Vec2,
        window_width: f32,
    };

    const CellSelection = struct {
        index: usize,
        editing: bool,
        just_selected: bool = true,
    };

    const AddressSpace = enum {
        cpu,
        ppu,
        oam,
    };

    pub fn init() HexEditor {
        return HexEditor{};
    }

    pub fn predraw(self: *HexEditor) !void {
        self.layout.char_size = blk: {
            var temp: Imgui.Vec2 = undefined;
            Imgui.calcTextSize(.{ &temp, "0", null, false, -1 });
            break :blk temp;
        };

        const style = try Imgui.getStyle();

        const address_width = @intToFloat(f32, self.layout.address_digits) * self.layout.char_size.x;
        const bytes_width = @intToFloat(f32, self.layout.bytes_per_line) * self.layout.char_size.x * 3;
        const spacing_width = @intToFloat(f32, self.layout.extra_spacing_every_8) * self.layout.char_size.x;
        const decoration_width = style.ScrollbarSize + style.WindowPadding.x * 2;
        self.layout.window_width = address_width +
            @intToFloat(f32, ": ".len) +
            bytes_width +
            @intToFloat(f32, @divTrunc(self.layout.bytes_per_line, 8)) * spacing_width +
            decoration_width;

        const this_avoids_a_miscompile = .{ .x = self.layout.window_width, .y = std.math.f32_max };
        Imgui.setNextWindowSizeConstraints(.{ .{ .x = 0, .y = 0 }, this_avoids_a_miscompile, null, null });
    }

    pub fn draw(self: *HexEditor, context: *ImguiContext) !bool {
        if (Imgui.beginMenuBar()) {
            defer Imgui.endMenuBar();

            if (Imgui.beginMenu(.{ "Memory", true })) {
                defer Imgui.endMenu();

                inline for (.{
                    .{ .label = "CPU", .address_space = .cpu },
                    .{ .label = "PPU", .address_space = .ppu },
                    .{ .label = "OAM", .address_space = .oam },
                }) |item_info| {
                    if (Imgui.menuItem(.{
                        item_info.label,
                        null,
                        self.address_space == item_info.address_space,
                        true,
                    })) {
                        self.address_space = item_info.address_space;
                    }
                }
            }
        }

        if (!context.console.cart.rom_loaded) {
            return true;
        }

        const draw_list = try Imgui.getWindowDrawList();

        // TODO: make/search for issue
        const this_avoids_a_miscompile = .{ .x = self.layout.char_size.x, .y = 0 };
        Imgui.pushStyleVarVec2(.{ c.ImGuiStyleVar_FramePadding, .{ .x = 0, .y = 0 } });
        Imgui.pushStyleVarVec2(.{ c.ImGuiStyleVar_ItemSpacing, this_avoids_a_miscompile });
        defer Imgui.popStyleVar(.{2});

        if (Imgui.isMouseClicked(.{ 0, false })) {
            self.cell_selection = null;
        }

        // TODO: StringBuilder/std.fmt.format are slow, consider custom toHex function
        // considering formatting will occur a lot here
        var str = util.StringBuilder.init(context.getParentContext().allocator);
        defer str.deinit();

        var clipper = try Imgui.listClipperInit();
        defer Imgui.listClipperDeinit(.{clipper});

        Imgui.listClipperBegin(.{ clipper, @intCast(c_int, self.getMaxAddr() / 16), self.layout.char_size.y });

        while (Imgui.listClipperStep(.{clipper})) {
            var i = @intCast(usize, clipper.DisplayStart * 16);
            while (i < clipper.DisplayEnd * 16) : (i += 1) {
                if (i & 15 == 0) {
                    str.reset();
                    _ = try std.fmt.format(str.writer(), "{x:0>4}: \x00", .{i});
                    Imgui.text(str.getSliceNull());
                    Imgui.sameLine(.{ 0, -1 });
                }

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
                        .{
                            .x = cursor_pos.x + self.layout.char_size.x * 2,
                            .y = cursor_pos.y + self.layout.char_size.y,
                        },
                        0xffd05050,
                        0,
                        0,
                    );
                }

                const byte = self.getMemoryValue(context.*, i);

                str.reset();
                _ = try std.fmt.format(str.writer(), "{x:0>2}\x00", .{byte});
                const str_slice = str.getSliceNull();

                if (is_selected and self.cell_selection != null and self.cell_selection.?.editing) {
                    const selection = &self.cell_selection.?;
                    Imgui.setNextItemWidth(.{self.layout.char_size.x * 2});

                    const was_just_selected = selection.just_selected;
                    // TODO: why does the mouse getting released unfocus the inputText?
                    if (selection.just_selected or (Imgui.isWindowFocused(.{0}) and Imgui.isMouseReleased(.{0}))) {
                        Imgui.setKeyboardFocusHere(.{0});
                        selection.just_selected = false;
                    }

                    Imgui.pushIdInt(.{@intCast(c_int, i)});
                    defer Imgui.popId();

                    // TODO: callback
                    if (Imgui.inputText(.{
                        "##hex input",
                        str_slice,
                        @sizeOf(@TypeOf(str_slice)), // wants raw size
                        Imgui.inputTextFlagsCharsHexadecimal |
                            //Imgui.inputTextFlagsEnterReturnsTrue |
                            Imgui.inputTextFlagsNoHorizontalScroll |
                            Imgui.inputTextFlagsAutoSelectAll |
                            Imgui.inputTextFlagsAlwaysOverwrite,
                        null,
                        null,
                    })) {
                        if (str_slice[2] != '\x00') {
                            // TODO: search for issue
                            std.log.warn("imgui broke our null terminator", .{});
                            str_slice[2] = '\x00';
                        }
                        if (!was_just_selected and str_slice[0] != '\x00' and str_slice[1] != '\x00') {
                            try self.setMemoryValue(context.*, i, str_slice[0..2]);
                            selection.index +|= 1;
                            selection.just_selected = true;
                        }
                    }
                } else {
                    Imgui.text(str_slice);
                }

                if (Imgui.isItemClicked(.{0})) {
                    self.cell_selection = CellSelection{
                        .index = i,
                        .editing = true,
                    };
                }

                if (i & 0xf != 0xf) {
                    const spacing = if (i & 0x7 == 0x7)
                        @intToFloat(f32, self.layout.extra_spacing_every_8 + 1) * self.layout.char_size.x
                    else
                        -1;
                    Imgui.sameLine(.{ 0, spacing });
                }
            }
        }

        return true;
    }

    fn getMaxAddr(self: HexEditor) usize {
        return switch (self.address_space) {
            .cpu => 0xffff,
            .ppu => 0x3fff,
            .oam => 0x0100,
        };
    }

    fn getMemoryValue(self: *HexEditor, context: ImguiContext, addr: usize) u8 {
        return switch (self.address_space) {
            .cpu => context.console.cpu.mem.peek(@truncate(u16, addr)),
            .ppu => context.console.ppu.mem.peek(@truncate(u14, addr)),
            .oam => context.console.ppu.oam.primary[addr],
        };
    }

    fn setMemoryValue(self: HexEditor, context: ImguiContext, addr: usize, str: []const u8) !void {
        std.debug.assert(str.len == 2);

        const val = try std.fmt.parseInt(u8, str, 16);

        switch (self.address_space) {
            .cpu => context.console.cpu.mem.sneak(@truncate(u16, addr), val),
            .ppu => context.console.ppu.mem.sneak(@truncate(u14, addr), val),
            .oam => context.console.ppu.oam.primary[addr] = val,
        }
    }
};
