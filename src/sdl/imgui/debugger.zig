const std = @import("std");
const Allocator = std.mem.Allocator;

const instruction_ = @import("../../instruction.zig");
const RawInstruction = instruction_.Instruction;
const Op = instruction_.Op;

const Imgui = @import("../bindings.zig").Imgui;

const ImguiContext = @import("../imgui.zig").ImguiContext;
const util = @import("util.zig");

const Console = @TypeOf(@as(ImguiContext, undefined).console);

pub const Debugger = struct {
    pub fn init() Debugger {
        return Debugger{};
    }

    pub fn draw(self: Debugger, context: *ImguiContext) !bool {
        _ = self;
        if (!context.console.cart.rom_loaded) {
            return true;
        }

        var decoder = InstructionDecoder.init(0x8000);

        const parent_context = context.getParentContext();

        var i: usize = 0;
        while (i < 100) : (i += 1) {
            var formatter = InstructionFormatter.init(parent_context.allocator, decoder.step(context.console));
            defer formatter.deinit();

            try formatter.update(context.console);
            Imgui.text(formatter.string.getSliceNull());
        }

        return true;
    }
};

const InstructionFormatter = struct {
    string: util.StringBuilder,
    instruction: Instruction,

    fn init(allocator: *Allocator, instruction: Instruction) InstructionFormatter {
        return InstructionFormatter{
            .string = util.StringBuilder.init(allocator),
            .instruction = instruction,
        };
    }

    fn deinit(self: InstructionFormatter) void {
        self.string.deinit();
    }

    fn update(self: *InstructionFormatter, console: Console) !void {
        var prev = self.instruction;
        self.instruction.update(console);

        // TODO: maybe use a better scheme to check if should make a new string
        if (self.string.getSlice().len > 0 and std.meta.eql(prev, self.instruction)) {
            return;
        }

        self.string.reset();
        try std.fmt.format(self.string.writer(), "{}", .{self.instruction});

        try self.string.nullTerminate();
    }
};

const Instruction = struct {
    address: u16,
    op: Op(.accurate),
    operands: Operands,

    // considered using the Addressing enum, but I want more information
    // the cpu collects that information as it runs, I need it right away
    // maybe use null instead of undefined initialization for explicitness
    /// All indirection following will be done at time decode,
    /// May require updating
    const Operands = union(enum) {
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
        };

        const ZeroPage = struct {
            index: ?Register,
            address: u8,

            effective_address: u8 = undefined,
            value: u8 = undefined,
        };

        const Absolute = struct {
            index: ?Register,
            address: u16,

            effective_address: u16 = undefined,
            value: u8 = undefined,
        };

        const Relative = struct {
            condition: struct {
                flag: enum { n, v, z, c },
                not: bool,
            },
            offset: i8,

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

    fn update(self: *Instruction, console: Console) void {
        const cpu = &console.cpu;
        const reg = &cpu.reg;
        const mem = &cpu.mem;

        switch (self.operands) {
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
                    x.next_address = @bitCast(u16, @bitCast(i16, self.address) +% x.offset) +% 2;
                } else {
                    x.next_address = self.address +% 2;
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
    addr: u16,

    fn init(addr: u16) InstructionDecoder {
        return InstructionDecoder{
            .addr = addr,
        };
    }

    fn step(self: *InstructionDecoder, console: Console) Instruction {
        const mem = &console.cpu.mem;

        const opcode = mem.peek(self.addr);
        const byte1 = mem.peek(self.addr +% 1);
        const byte2 = mem.peek(self.addr +% 2);

        const instruction = RawInstruction(.accurate).decode(opcode);

        const operands: Instruction.Operands = blk: {
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
                    } };
                },
                .indirect_x => break :blk .{ .indirect_x = .{ .address = byte1 } },
                .indirect_y => break :blk .{ .indirect_y = .{ .address = byte1 } },
                .special => unreachable,
            }
        };

        var decoded = Instruction{
            .address = self.addr,
            .op = instruction.op,
            .operands = operands,
        };
        //decoded.update(console);

        if (opcode == 0x00) {
            self.addr += 2;
        } else {
            self.addr += switch (operands) {
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
        }

        return decoded;
    }
};
