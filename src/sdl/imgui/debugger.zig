const std = @import("std");
const Allocator = std.mem.Allocator;

const instruction_ = @import("../../instruction.zig");
const RawInstruction = instruction_.Instruction;
const Op = instruction_.Op;

const bindings = @import("../bindings.zig");
const c = bindings.c;
const Imgui = bindings.Imgui;

const ImguiContext = @import("../imgui.zig").ImguiContext;
const util = @import("util.zig");

const Console = @TypeOf(@as(ImguiContext, undefined).console.*);
const MapperState = @import("../../mapper.zig").MapperState;

pub const Debugger = struct {
    layout: Layout = Layout{
        .char_size = .{
            .x = 0,
            .y = 0,
        },
    },

    // TODO: strongly consider allocating one big text pool and taking from that
    // instead of having heap allocated memory strewn about
    formatters: []InstructionFormatter,
    last_formatter: usize = 0,

    last_update_cycle: usize = 0,
    pc_index: ?usize = null,
    follow_pc: bool = true,

    const Layout = struct {
        char_size: Imgui.Vec2,
    };

    pub fn init(allocator: *Allocator) !Debugger {
        const formatters = try allocator.alloc(InstructionFormatter, 0x8000);
        for (formatters) |*formatter| {
            formatter.* = try InstructionFormatter.init(allocator);
        }
        return Debugger{
            .formatters = formatters,
        };
    }

    pub fn deinit(self: Debugger, allocator: *Allocator) void {
        for (self.formatters) |formatter| {
            formatter.deinit();
        }
        allocator.free(self.formatters);
    }

    pub fn predraw(self: *Debugger) void {
        self.layout.char_size = blk: {
            var temp: Imgui.Vec2 = undefined;
            Imgui.calcTextSize(.{ &temp, "0", null, false, -1 });
            break :blk temp;
        };

        Imgui.pushStyleVarVec2(.{ c.ImGuiStyleVar_WindowPadding, .{ .x = 0, .y = 0 } });
    }

    pub fn postdraw(_: Debugger) void {
        Imgui.popStyleVar(.{1});
    }

    pub fn draw(self: *Debugger, context: *ImguiContext) !bool {
        if (!context.console.cart.rom_loaded) {
            return true;
        }

        try self.drawControlHeader(context);
        try self.drawInstructionList(context.*);

        return true;
    }

    fn drawControlHeader(self: Debugger, context: *ImguiContext) !void {
        const style = try Imgui.getStyle();

        const padding = 4;
        const lines = 1;
        const size = .{ .x = 0, .y = padding * 2 + self.layout.char_size.y * lines + style.ItemSpacing.y * (lines - 1) };

        const menubar_color = try Imgui.getStyleColor(.{c.ImGuiCol_MenuBarBg});
        Imgui.pushStyleColorVec4(.{ c.ImGuiCol_ChildBg, menubar_color.* });
        defer Imgui.popStyleColor(.{1});

        Imgui.pushStyleVarVec2(.{ c.ImGuiStyleVar_WindowPadding, .{ .x = padding, .y = padding } });
        defer Imgui.popStyleVar(.{1});

        defer Imgui.endChild();
        if (Imgui.beginChild(.{
            "Control Header",
            size,
            false,
            Imgui.windowFlagsAlwaysUseWindowPadding,
        })) {
            Imgui.pushStyleVarVec2(.{ c.ImGuiStyleVar_FramePadding, .{ .x = 0, .y = 0 } });
            defer Imgui.popStyleVar(.{1});

            if (Imgui.button(.{ "Step Over", .{ .x = 0, .y = 0 } })) {
                try context.pause();
                context.console.cpu.runStep();
                context.console.cpu.runUntilNextInstruction();
            }

            Imgui.sameLine(.{ 0, -1 });

            var str = util.StringBuilder.init(context.getParentContext().allocator);
            defer str.deinit();

            try std.fmt.format(str.writer(), "PC: {x:0>4}\x00", .{context.console.cpu.reg.pc});
            Imgui.text(str.getSliceNull());
        }
    }

    // TODO: possible to merge this with drawInstructionList to only update
    // to the end of the scrolled region
    fn updateInstructionFormatters(self: *Debugger, context: ImguiContext) !void {
        const mapper_state = context.console.cart.getMapperState();
        const pc = context.console.cpu.reg.pc;
        self.pc_index = null;

        var decoder = InstructionDecoder.init(context.console, 0x8000);
        var redo_rest = false;
        var next_is_realigned = false;
        for (self.formatters) |*formatter, i| {
            var prev_address = decoder.address;

            if (decoder.address == pc) {
                self.pc_index = i;
            }

            if (redo_rest or
                next_is_realigned or
                formatter.instruction == null or
                formatter.instruction.?.bytes[0] != decoder.nextOpcode())
            {
                if (formatter.instruction) |instruction| {
                    const realigned_address = instruction.mapped_address;
                    const realigned_opcode = context.console.cpu.mem.peek(realigned_address);

                    if (instruction.bytes[0] == realigned_opcode and formatter.is_realigned) {
                        if (realigned_address == decoder.address) {
                            formatter.is_realigned = false;
                        } else {
                            decoder.address = realigned_address;
                            prev_address = decoder.address;
                        }
                    }
                }
                formatter.is_realigned = formatter.is_realigned or next_is_realigned;

                formatter.instruction = decoder.step();
                try formatter.update(context.console, true);
                redo_rest = true;
            } else if (formatter.instruction) |instruction| {
                decoder.address +%= instruction.size;
                try formatter.update(context.console, false);
            }

            if (prev_address > decoder.address) {
                self.last_formatter = i;
                break;
            }

            // realign to banks and pc, it's an ok solution for now
            const prev_bank = @truncate(u15, prev_address) >> mapper_state.prg_rom_bank_bits;
            const current_bank = @truncate(u15, decoder.address) >> mapper_state.prg_rom_bank_bits;
            if (prev_bank != current_bank) {
                decoder.address = 0x8000 | (@as(u16, current_bank) << mapper_state.prg_rom_bank_bits);
            } else if (prev_address < pc and decoder.address > pc) {
                decoder.address = pc;
            } else {
                next_is_realigned = false;
                continue;
            }

            next_is_realigned = true;
        }
    }

    fn drawInstructionList(self: *Debugger, context: ImguiContext) !void {
        const state_changed = context.paused and self.last_update_cycle != context.console.cpu.cycles;
        if (state_changed) {
            try self.updateInstructionFormatters(context);
            self.last_update_cycle = context.console.cpu.cycles;
        }

        defer Imgui.endChild();
        if (Imgui.beginChild(.{ "Instruction List", .{ .x = 0, .y = 0 }, false, Imgui.windowFlagsNone })) {
            const pc = context.console.cpu.reg.pc;
            if (state_changed and self.follow_pc) {
                if (self.pc_index) |pc_index| {
                    const style = try Imgui.getStyle();
                    c.igSetScrollY_Float(@intToFloat(f32, pc_index) * (self.layout.char_size.y + style.ItemSpacing.y));
                }
            }

            const draw_list = try Imgui.getWindowDrawList();

            var clipper = try Imgui.listClipperInit();
            defer Imgui.listClipperDeinit(.{clipper});

            Imgui.listClipperBegin(.{ clipper, @intCast(c_int, self.last_formatter), -1.0 });
            while (Imgui.listClipperStep(.{clipper})) {
                var i = @intCast(usize, clipper.DisplayStart);
                while (i < clipper.DisplayEnd) : (i += 1) {
                    const formatter = self.formatters[i];

                    if (formatter.is_realigned) {
                        c.igSeparator();
                    }

                    if (formatter.instruction) |instruction| {
                        if (instruction.mapped_address == pc) {
                            const cursor_pos = blk: {
                                var temp: Imgui.Vec2 = undefined;
                                Imgui.getCursorScreenPos(.{&temp});
                                break :blk temp;
                            };

                            const window_width = Imgui.getWindowWidth();

                            c.ImDrawList_AddRectFilled(
                                draw_list,
                                cursor_pos,
                                .{
                                    .x = cursor_pos.x + window_width,
                                    .y = cursor_pos.y + self.layout.char_size.y,
                                },
                                0xffd05050,
                                0,
                                0,
                            );
                        }
                    }

                    Imgui.text(self.formatters[i].string.getSliceNull());
                }
            }
        }
    }
};

const InstructionFormatter = struct {
    string: util.StringBuilder,
    instruction: ?Instruction = null,
    is_realigned: bool = false,

    fn init(allocator: *Allocator) !InstructionFormatter {
        return InstructionFormatter{
            .string = try util.StringBuilder.initCapacity(allocator, 64),
        };
    }

    fn deinit(self: InstructionFormatter) void {
        self.string.deinit();
    }

    fn update(self: *InstructionFormatter, console: *Console, force_update: bool) !void {
        if (self.instruction == null) {
            @panic("InstructionFormatter has no instruction");
        }

        const prev = self.instruction.?;
        const instruction = &self.instruction.?;
        instruction.update(console);

        // TODO: maybe use a better scheme to check if should make a new string
        if (self.string.getSlice().len > 0 and std.meta.eql(prev, instruction.*) and !force_update) {
            return;
        }

        // these positions all assume the longest possible string length
        const bytes_pos = "MM:AAAA: ".len;
        const mnemonics_pos = bytes_pos + "BB BB BB     ".len;
        const comments_pos = mnemonics_pos + "III $AAAA,I[#$OO] ".len;

        self.string.reset();
        const writer = self.string.writer();
        try std.fmt.format(writer, "{x:0>2}:{x:0>4}: ", .{
            instruction.rom_bank,
            instruction.mapped_address,
        });

        for (instruction.bytes[0..instruction.size]) |b| {
            try std.fmt.format(writer, "{x:0>2} ", .{b});
        }

        try self.alignSpacing(mnemonics_pos);

        if (instruction.operands == .undocumented) {
            try std.fmt.format(writer, "ILL\x00", .{});
            return;
        } else {
            try std.fmt.format(writer, "{s}", .{instruction_.opToString(instruction.op)});
        }

        switch (instruction.operands) {
            .undocumented => unreachable,

            .implied => {},
            .immediate => |x| try std.fmt.format(writer, " #${x:0>2}", .{x}),
            .jump_direct => |x| try std.fmt.format(writer, " ${x:0>4}", .{x}),

            .accumulator => |x| try std.fmt.format(writer, " A[#${x:0>2}]", .{x}),
            .zero_page => |x| {
                try std.fmt.format(writer, " ${x:0>2}", .{x.address});
                if (x.index) |register| {
                    try writer.writeByte(',');
                    try self.formatRegister(register, x.index_value);
                }
                try self.alignSpacing(comments_pos);
                try std.fmt.format(writer, "; ", .{});
                try self.formatPointer(u8, x.effective_address, x.value);
            },
            .absolute => |x| {
                try std.fmt.format(writer, " ${x:0>4}", .{x.address});
                if (x.index) |register| {
                    try writer.writeByte(',');
                    try self.formatRegister(register, x.index_value);
                }
                try self.alignSpacing(comments_pos);
                try std.fmt.format(writer, "; ", .{});
                try self.formatPointer(u8, x.effective_address, x.value);
            },
            .relative => |x| {
                try std.fmt.format(writer, " ${x:0>2}[${x:0>4}]", .{ @bitCast(u8, x.offset), x.jump_address });
                try self.alignSpacing(comments_pos);

                // TODO: prefix variable avoids miscompile :/
                // https://github.com/ziglang/zig/issues/5230
                const prefix = if (x.condition.not) "!" else "";
                try std.fmt.format(writer, "; {s}{s} -> {}", .{
                    prefix,
                    @tagName(x.condition.flag),
                    x.will_jump,
                });
            },
            .indirect_x => |x| {
                try std.fmt.format(writer, " (${x:0>2},X)", .{x.address});
                try self.alignSpacing(comments_pos);
                try std.fmt.format(writer, "; ", .{});
                try self.formatPointer(u8, x.effective_address, x.value);
            },
            .indirect_y => |x| {
                try std.fmt.format(writer, " (${x:0>2}),Y", .{x.address});
                try self.alignSpacing(comments_pos);
                try std.fmt.format(writer, "; ", .{});
                try self.formatPointer(u8, x.effective_address, x.value);
            },
            .jump_indirect => |x| {
                try std.fmt.format(writer, " (${x:0>4})", .{x.address});
                try self.alignSpacing(comments_pos);
                try std.fmt.format(writer, "; ${x:0>4}", .{x.effective_address});
            },
            .ret => |x| {
                try self.alignSpacing(comments_pos);
                try std.fmt.format(writer, "; ${x:0>4}", .{x.return_address});
            },
        }

        try self.string.nullTerminate();
    }

    /// Prints spaces until the string builder length is line_length
    fn alignSpacing(self: *InstructionFormatter, line_length: usize) !void {
        const str_len = self.string.getSlice().len;
        if (line_length < str_len) {
            std.log.err("InstructionFormatter.alignSpacing: line_length ({}) < str_len ({})", .{
                line_length,
                str_len,
            });
            return;
        }
        return self.string.writer().writeByteNTimes(' ', line_length - str_len);
    }

    fn formatRegister(self: *InstructionFormatter, register: Instruction.Operands.Register, value: u8) !void {
        return std.fmt.format(self.string.writer(), "{s}[#${x:0>2}]", .{ register.getString(), value });
    }

    fn formatPointer(
        self: *InstructionFormatter,
        comptime T: type,
        address: u16,
        value: T,
    ) !void {
        std.debug.assert(T == u8 or T == u16);

        const nibble_count: u3 = @divExact(@typeInfo(T).Int.bits, 4);
        const digit_char: u8 = @as(u8, '0') + nibble_count;
        const format_str = "*(${x:0>4}) = {x:0>" ++ [1]u8{digit_char} ++ "}";
        return std.fmt.format(self.string.writer(), format_str, .{ address, value });
    }
};

const Instruction = struct {
    rom_bank: usize,
    mapped_address: u16,
    bytes: [3]u8,
    size: u2,

    op: Op(.accurate),
    operands: Operands,

    // considered using the Addressing enum, but I want more information
    // the cpu collects that information as it runs, I need it right away
    // maybe use null instead of undefined initialization for explicitness
    /// All indirection following will be done at time decode,
    /// May require updating
    const Operands = union(enum) {
        undocumented,

        // Initialized at start, constant
        implied,
        immediate: u8,
        jump_direct: u16,

        // Partially/fully initialized via updating
        accumulator: u8,
        zero_page: ZeroPage,
        absolute: Absolute,
        relative: Relative,
        indirect_x: IndirectX,
        indirect_y: IndirectY,
        jump_indirect: JumpIndirect,
        ret: Return,

        const Register = enum {
            x,
            y,

            fn getString(self: Register) []const u8 {
                return switch (self) {
                    .x => "X",
                    .y => "Y",
                };
            }
        };

        const ZeroPage = struct {
            index: ?Register,
            address: u8,

            index_value: u8 = undefined,
            effective_address: u8 = undefined,
            value: u8 = undefined,
        };

        const Absolute = struct {
            index: ?Register,
            address: u16,

            index_value: u8 = undefined,
            effective_address: u16 = undefined,
            value: u8 = undefined,
        };

        const Relative = struct {
            condition: struct {
                flag: enum { n, v, z, c },
                not: bool,
            },
            offset: i8,
            jump_address: u16,

            will_jump: bool = undefined,
            next_address: u16 = undefined,
        };

        const IndirectX = struct {
            address: u8,

            effective_address: u16 = undefined,
            value: u8 = undefined,
        };

        const IndirectY = struct {
            address: u8,

            preindexed_address: u16 = undefined,
            effective_address: u16 = undefined,
            value: u8 = undefined,
        };

        const JumpIndirect = struct {
            address: u16,

            effective_address: u16 = undefined,
        };

        const Return = struct {
            ret_type: enum { interrupt, subroutine },

            return_address: u16 = undefined,
        };
    };

    fn update(self: *Instruction, console: *Console) void {
        const cpu = &console.cpu;
        const reg = &cpu.reg;
        const mem = &cpu.mem;

        switch (self.operands) {
            .undocumented => {},

            .implied => {},
            .immediate => {},
            .jump_direct => {},

            .accumulator => |*x| x.* = reg.a,
            .zero_page => |*x| {
                const index = if (x.index) |i|
                    switch (i) {
                        .x => reg.x,
                        .y => reg.y,
                    }
                else
                    0;
                x.index_value = index;
                x.effective_address = x.address +% index;
                x.value = mem.peek(x.effective_address);
            },
            .absolute => |*x| {
                const index = if (x.index) |i|
                    switch (i) {
                        .x => reg.x,
                        .y => reg.y,
                    }
                else
                    0;
                x.index_value = index;
                x.effective_address = x.address +% index;
                x.value = mem.peek(x.effective_address);
            },
            .relative => |*x| {
                const flag_value = switch (x.condition.flag) {
                    .n => reg.getFlag("N"),
                    .v => reg.getFlag("V"),
                    .z => reg.getFlag("Z"),
                    .c => reg.getFlag("C"),
                };

                x.will_jump = flag_value != x.condition.not;
                if (x.will_jump) {
                    x.next_address = x.jump_address;
                } else {
                    x.next_address = self.mapped_address +% 2;
                }
            },
            .indirect_x => |*x| {
                const addr_low = mem.peek(x.address +% reg.x);
                const addr_high: u16 = mem.peek(x.address +% reg.x +% 1);

                x.effective_address = (addr_high << 8) | addr_low;
                x.value = mem.peek(x.effective_address);
            },
            .indirect_y => |*x| {
                const addr_low = mem.peek(x.address);
                const addr_high: u16 = mem.peek(x.address +% 1);

                x.preindexed_address = (addr_high << 8) | addr_low;
                x.effective_address = x.preindexed_address +% reg.y;
                x.value = mem.peek(x.effective_address);
            },
            .jump_indirect => |*x| {
                x.effective_address = mem.peek(x.address);
            },
            .ret => |*x| {
                const stack_pointer = switch (x.ret_type) {
                    .interrupt => reg.s +% 2,
                    .subroutine => reg.s +% 1,
                };

                const low_byte = mem.peek(@as(u16, 0x100) | stack_pointer);
                const high_byte: u16 = mem.peek(@as(u16, 0x100) | (stack_pointer +% 1));

                x.return_address = (high_byte << 8) | low_byte;
            },
        }
    }
};

const InstructionDecoder = struct {
    console: *Console,
    address: u16,
    mapper_state: MapperState,

    fn init(console: *Console, address: u16) InstructionDecoder {
        return InstructionDecoder{
            .console = console,
            .address = address,
            .mapper_state = console.cart.getMapperState(),
        };
    }

    fn bytesToBankBoundary(self: InstructionDecoder) usize {
        const addr_in_bank = @truncate(u15, self.address) & self.mapper_state.prg_rom_bank_size;
        return self.mapper_state.prg_rom_bank_size - addr_in_bank;
    }

    fn getCurrentRomBank(self: InstructionDecoder) usize {
        const selected = @truncate(u15, self.address) >> self.mapper_state.prg_rom_bank_bits;
        return self.mapper_state.prg_rom_selected_banks[selected] >> self.mapper_state.prg_rom_bank_bits;
    }

    fn nextOpcode(self: InstructionDecoder) u8 {
        return self.console.cpu.mem.peek(self.address);
    }

    fn step(self: *InstructionDecoder) Instruction {
        const console = self.console;
        const mem = &console.cpu.mem;

        const opcode = mem.peek(self.address);
        const byte1 = mem.peek(self.address +% 1);
        const byte2 = mem.peek(self.address +% 2);

        const instruction = RawInstruction(.accurate).decode(opcode);

        const operands: Instruction.Operands = blk: {
            // TODO: make toggleable
            if (!instruction_.opIsDocumented(instruction.op)) {
                break :blk .{ .undocumented = .{} };
            }
            switch (opcode) {
                0x0a, 0x2a, 0x4a, 0x6a => break :blk .{ .accumulator = undefined },
                0x00, 0x08, 0x28, 0x48, 0x68 => break :blk .{ .implied = .{} },
                0x20, 0x4c => break :blk .{ .jump_direct = (@as(u16, byte2) << 8) | byte1 },
                0x6c => break :blk .{ .jump_indirect = .{
                    .address = (@as(u16, byte2) << 8) | byte1,
                } },
                0x40 => break :blk .{ .ret = .{ .ret_type = .interrupt } },
                0x60 => break :blk .{ .ret = .{ .ret_type = .subroutine } },
                else => {},
            }
            switch (instruction.addressing) {
                .implied => break :blk .{ .implied = .{} },
                .immediate => break :blk .{ .immediate = byte1 },
                .zero_page, .zero_page_x, .zero_page_y => {
                    const index: ?Instruction.Operands.Register =
                        switch (instruction.addressing) {
                        .zero_page => null,
                        .zero_page_x => .x,
                        .zero_page_y => .y,
                        else => unreachable,
                    };
                    const addr = byte1;
                    break :blk .{ .zero_page = .{
                        .index = index,
                        .address = addr,
                    } };
                },
                .absolute, .absolute_x, .absolute_y => {
                    const index: ?Instruction.Operands.Register =
                        switch (instruction.addressing) {
                        .absolute => null,
                        .absolute_x => .x,
                        .absolute_y => .y,
                        else => unreachable,
                    };
                    const addr = (@as(u16, byte2) << 8) | byte1;
                    break :blk .{ .absolute = .{
                        .index = index,
                        .address = addr,
                    } };
                },
                .relative => {
                    const Condition = blk2: {
                        const dummy = @as(Instruction.Operands.Relative, undefined);
                        break :blk2 @TypeOf(dummy.condition);
                    };
                    const condition: Condition = switch (opcode) {
                        0x10 => .{ .flag = .n, .not = true },
                        0x30 => .{ .flag = .n, .not = false },
                        0x50 => .{ .flag = .v, .not = true },
                        0x70 => .{ .flag = .v, .not = false },
                        0x90 => .{ .flag = .c, .not = true },
                        0xb0 => .{ .flag = .c, .not = false },
                        0xd0 => .{ .flag = .z, .not = true },
                        0xf0 => .{ .flag = .z, .not = false },
                        else => unreachable,
                    };
                    const offset = @bitCast(i8, byte1);
                    break :blk .{ .relative = .{
                        .condition = condition,
                        .offset = offset,
                        .jump_address = @bitCast(u16, @bitCast(i16, self.address) +% offset) +% 2,
                    } };
                },
                .indirect_x => break :blk .{ .indirect_x = .{ .address = byte1 } },
                .indirect_y => break :blk .{ .indirect_y = .{ .address = byte1 } },
                .special => unreachable,
            }
        };

        const instruction_size = //if (opcode == 0x00)
            // 2
            //else
            switch (operands) {
            .undocumented => 1,

            .implied => 1,
            .immediate => 2,
            .jump_direct => 2,

            .accumulator => @as(u2, 1),
            .zero_page => 2,
            .absolute => 3,
            .relative => 2,
            .indirect_x, .indirect_y => 2,
            .jump_indirect => 3,
            .ret => 1,
        };

        const result = Instruction{
            .rom_bank = self.getCurrentRomBank(),
            .mapped_address = self.address,
            .bytes = [3]u8{ opcode, byte1, byte2 },
            .size = instruction_size,

            .op = instruction.op,
            .operands = operands,
        };

        self.address +%= instruction_size;

        return result;
    }
};
