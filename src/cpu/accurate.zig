const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("common.zig");

const instruction_ = @import("../instruction.zig");
const Op = instruction_.Op;
const Addressing = instruction_.Addressing;
const Access = instruction_.Access;
const Instruction = instruction_.Instruction;
const opToString = instruction_.opToString;

const console_ = @import("../console.zig");
const Config = console_.Config;
const Console = console_.Console;

const Cart = @import("../cart.zig").Cart;
const Ppu = @import("../ppu.zig").Ppu;
const Apu = @import("../apu.zig").Apu;
const Controller = @import("../controller.zig").Controller;

const flags = @import("../flags.zig");

pub fn Cpu(comptime config: Config) type {
    return struct {
        const Self = @This();

        reg: common.Registers,
        mem: Memory(config),
        ppu: *Ppu(config),
        apu: *Apu(config),

        irq_pin: IrqSource = std.mem.zeroes(IrqSource),
        nmi_pin: bool = false,

        interrupt_acknowledged: bool = false,
        interrupt_at_check: Interrupt = undefined,

        cycles: usize = 0,

        state: ExecState = .{
            .opcode = 0,
            .op = .op_brk,
            .addressing = .implied,
            .access = .read,
        },

        const IrqSource = packed struct {
            brk: bool,
            apu_frame_counter: bool,
            mapper: bool,
            padding: u5,

            pub fn value(self: IrqSource) u8 {
                return @bitCast(u8, self);
            }
        };

        const Interrupt = enum {
            irq,
            nmi,
        };

        const ExecState = struct {
            opcode: u8,
            op: Op(.accurate),
            addressing: Addressing(.accurate),
            access: Access,
            cycle: u4 = 0,

            // values constructed during opcode execution
            // use is instruction specific
            c_byte: u8 = 0,
            c_addr: u16 = 0,
        };

        pub fn init(console: *Console(config)) Self {
            return Self{
                .reg = common.Registers.startup(),
                .mem = Memory(config).zeroes(&console.cart, &console.ppu, &console.apu, &console.controller),
                .ppu = &console.ppu,
                .apu = &console.apu,
            };
        }

        pub fn deinit(_: Self) void {}

        pub fn reset(self: *Self) void {
            flags.setMask(u16, &self.reg.pc, self.mem.peek(0xfffc), 0xff);
            flags.setMask(u16, &self.reg.pc, @as(u16, self.mem.peek(0xfffd)) << 8, 0xff00);
            std.log.debug("PC set to {x:0>4}", .{self.reg.pc});
        }

        pub fn setIrqSource(self: *Self, comptime source: []const u8) void {
            @field(self.irq_pin, source) = true;
        }

        pub fn clearIrqSource(self: *Self, comptime source: []const u8) void {
            @field(self.irq_pin, source) = false;
        }

        pub fn setNmi(self: *Self) void {
            self.nmi_pin = true;
        }

        fn dma(self: *Self, addr_high: u8) void {
            // will set open_bus via mem.read, check if accurate
            const oam_addr = self.ppu.reg.oam_addr;
            var i: usize = 0;
            while (i < 256) : (i += 1) {
                const oam_i: u8 = oam_addr +% @truncate(u8, i);
                self.ppu.oam.primary[oam_i] = self.mem.read((@as(u16, addr_high) << 8) | @truncate(u8, i));

                common.cpuCycled(self);
                common.cpuCycled(self);
            }
        }

        fn readStack(self: *Self) u8 {
            return self.mem.read(0x100 | @as(u9, self.reg.s));
        }

        fn pushStack(self: *Self, val: u8) void {
            self.mem.write(0x100 | @as(u9, self.reg.s), val);
            self.reg.s -%= 1;
        }

        fn cycleSideEffects(self: *Self) void {
            common.cpuCycled(self);
            self.state.cycle +%= 1;
            self.cycles += 1;
        }

        pub fn runStep(self: *Self) void {
            // TODO: accurate interrupt polling
            if (!self.interrupt_acknowledged) {
                switch (self.state.cycle) {
                    0 => if (!self.pollInterrupt()) {
                        self.runCycle0();
                    },
                    1 => self.runCycle1(),
                    2 => self.runCycle2(),
                    3 => self.runCycle3(),
                    4 => self.runCycle4(),
                    5 => self.runCycle5(),
                    6 => self.runCycle6(),
                    7 => self.runCycle7(),
                    // 8 => {},
                    else => unreachable,
                }
            }
            if (self.interrupt_acknowledged) {
                self.execInterrupt();
            }

            if (@import("build_options").log_step) {
                self.logCycle();
            }
            self.cycleSideEffects();
        }

        /// Dummy read
        fn readNextByte(self: *Self) void {
            _ = self.mem.read(self.reg.pc);
        }

        /// Increment PC, byte is part of instruction
        fn fetchNextByte(self: *Self) u8 {
            self.readNextByte();
            self.reg.pc +%= 1;
            return self.mem.open_bus;
        }

        fn finishInstruction(self: *Self) void {
            // janky way to get it back to 0 as it's incremented right after this
            self.state.cycle = std.math.maxInt(u4);
        }

        fn pollInterrupt(self: *Self) bool {
            if (self.nmi_pin or (!self.reg.getFlag("I") and self.irq_pin.value() != 0)) {
                self.state.cycle = 0;
                self.interrupt_acknowledged = true;
                return true;
            }
            return false;
        }

        fn execInterrupt(self: *Self) void {
            switch (self.state.cycle) {
                0 => {
                    self.readNextByte();
                    self.state.op = .op_brk;
                    self.state.opcode = 0;
                },
                1 => self.readNextByte(),
                2 => self.pushStack(@truncate(u8, self.reg.pc >> 8)),
                3 => self.pushStack(@truncate(u8, self.reg.pc)),
                4 => {
                    const brk_flag = if (self.irq_pin.brk) @as(u8, 0x10) else 0;
                    self.pushStack(self.reg.p | 0b0010_0000 | brk_flag);

                    if (self.nmi_pin) {
                        self.interrupt_at_check = .nmi;
                        self.nmi_pin = false;
                    } else {
                        self.interrupt_at_check = .irq;
                        self.irq_pin.brk = false;
                    }
                },
                5 => {
                    const addr: u16 = switch (self.interrupt_at_check) {
                        .irq => 0xfffe,
                        .nmi => 0xfffa,
                    };
                    const low = self.mem.read(addr);
                    flags.setMask(u16, &self.reg.pc, low, 0xff);
                    self.reg.setFlag("I", true);
                },
                6 => {
                    const addr: u16 = switch (self.interrupt_at_check) {
                        .irq => 0xffff,
                        .nmi => 0xfffb,
                    };
                    const high: u16 = self.mem.read(addr);
                    flags.setMask(u16, &self.reg.pc, high << 8, 0xff00);

                    self.interrupt_acknowledged = false;
                    self.finishInstruction();
                },
                else => unreachable,
            }
        }

        fn setStateFromOpcode(self: *Self, opcode: u8) void {
            const instruction = Instruction(.accurate).decode(opcode);

            self.state.opcode = opcode;
            self.state.op = instruction.op;
            self.state.addressing = instruction.addressing;
            self.state.access = instruction.access;
        }

        fn runCycle0(self: *Self) void {
            const opcode = self.fetchNextByte();
            self.setStateFromOpcode(opcode);
        }

        fn runCycle1(self: *Self) void {
            switch (self.state.addressing) {
                .special => self.runCycle1Special(),
                .absolute, .absoluteX, .absoluteY => _ = self.fetchNextByte(),
                .indirectX, .indirectY, .relative => self.state.c_byte = self.fetchNextByte(),
                .implied => self.runCycle1Implied(),
                .immediate => self.runCycle1Immediate(),
                .zeroPage, .zeroPageX, .zeroPageY => self.state.c_addr = self.fetchNextByte(),
            }
        }

        fn runCycle2(self: *Self) void {
            switch (self.state.addressing) {
                .special => self.runCycle2Special(),
                .absolute => self.runCycle2Absolute(),
                .absoluteX => self.runCycle2AbsoluteIndexed(self.reg.x),
                .absoluteY => self.runCycle2AbsoluteIndexed(self.reg.y),
                .indirectX => self.runCycle2IndirectX(),
                .indirectY => _ = self.mem.read(self.state.c_byte),
                .relative => self.runCycle2Relative(),
                .zeroPage => self.runCycleAccess0(),
                .zeroPageX => self.runCycle2ZpIndirect(self.reg.x),
                .zeroPageY => self.runCycle2ZpIndirect(self.reg.y),
                else => unreachable,
            }
        }

        fn runCycle3(self: *Self) void {
            switch (self.state.addressing) {
                .special => self.runCycle3Special(),
                .absolute => self.runCycleAccess0(),
                .absoluteX => self.runCycle3AbsoluteIndexed(self.reg.x),
                .absoluteY => self.runCycle3AbsoluteIndexed(self.reg.y),
                .indirectX => _ = self.mem.read(self.state.c_byte),
                .indirectY => self.runCycle3IndirectY(),
                .relative => self.runCycle3Relative(),
                .zeroPage => self.runCycleAccess1(),
                .zeroPageX, .zeroPageY => self.runCycleAccess0(),
                else => unreachable,
            }
        }

        fn runCycle4(self: *Self) void {
            switch (self.state.addressing) {
                .special => self.runCycle4Special(),
                .absolute => self.runCycleAccess1(),
                .absoluteX, .absoluteY => self.runCycleAccess0(),
                .relative => self.runCycle4Relative(),
                .indirectX => self.runCycle4IndirectX(),
                .indirectY => self.runCycle4IndirectY(),
                .zeroPage => self.runCycleAccess2(),
                .zeroPageX, .zeroPageY => self.runCycleAccess1(),
                else => unreachable,
            }
        }

        fn runCycle5(self: *Self) void {
            switch (self.state.addressing) {
                .special => self.runCycle5Special(),
                .absolute => self.runCycleAccess2(),
                .absoluteX, .absoluteY => self.runCycleAccess1(),
                .indirectX, .indirectY => self.runCycleAccess0(),
                .zeroPageX, .zeroPageY => self.runCycleAccess2(),
                else => unreachable,
            }
        }

        fn runCycle6(self: *Self) void {
            switch (self.state.addressing) {
                .absoluteX, .absoluteY => self.runCycleAccess2(),
                .indirectX, .indirectY => self.runCycleAccess1(),
                else => unreachable,
            }
        }

        fn runCycle7(self: *Self) void {
            switch (self.state.addressing) {
                .indirectX, .indirectY => self.runCycleAccess2(),
                else => unreachable,
            }
        }

        /// These are for a pattern that seems to usually be followed
        /// after addressing specific logic
        /// The cycle they occur on relative to the current instruction
        /// depends on the addressing mode
        fn runCycleAccess0(self: *Self) void {
            switch (self.state.access) {
                .read => {
                    self.state.c_byte = self.mem.read(self.state.c_addr);
                    self.execOpcode();
                },
                .rmw => self.state.c_byte = self.mem.read(self.state.c_addr),
                .write => self.execOpcode(),
                else => unreachable,
            }
        }

        fn runCycleAccess1(self: *Self) void {
            std.debug.assert(self.state.access == .rmw);
            self.mem.write(self.state.c_addr, self.state.c_byte);
        }

        fn runCycleAccess2(self: *Self) void {
            std.debug.assert(self.state.access == .rmw);
            self.execOpcode();
        }

        fn runCycle1Special(self: *Self) void {
            switch (self.state.op) {
                .op_brk, .op_jmp, .op_jsr => self.state.c_byte = self.fetchNextByte(),
                .op_rti, .op_rts, .op_pha, .op_php, .op_pla, .op_plp => self.readNextByte(),
                else => unreachable,
            }
        }

        fn runCycle1Implied(self: *Self) void {
            self.readNextByte();
            self.execOpcode();
        }

        fn runCycle1Immediate(self: *Self) void {
            self.state.c_byte = self.fetchNextByte();
            self.execOpcode();
        }

        fn runCycle2Special(self: *Self) void {
            switch (self.state.op) {
                .op_brk => {
                    self.setIrqSource("brk");
                    self.interrupt_acknowledged = true;
                    self.state.cycle = 2;
                },
                .op_jmp => switch (self.state.opcode) {
                    0x4c => {
                        const low = self.state.c_byte;
                        const high: u16 = self.fetchNextByte();
                        self.reg.pc = (high << 8) | low;
                        self.finishInstruction();
                    },
                    0x6c => {
                        const low = self.state.c_byte;
                        const high: u16 = self.fetchNextByte();
                        self.state.c_addr = (high << 8) | low;
                    },
                    else => unreachable,
                },
                .op_jsr => {}, // unsure/subtle
                .op_pha => {
                    self.pushStack(self.reg.a);
                    self.finishInstruction();
                },
                .op_php => {
                    self.pushStack(self.reg.p | 0b0011_0000);
                    self.finishInstruction();
                },
                .op_pla, .op_plp, .op_rti, .op_rts => self.reg.s +%= 1,
                else => unreachable,
            }
        }

        fn runCycle2Absolute(self: *Self) void {
            const low = self.mem.open_bus;
            const high: u16 = self.fetchNextByte();
            self.state.c_addr = (high << 8) | low;
        }

        fn runCycle2AbsoluteIndexed(self: *Self, register: u8) void {
            const low = self.mem.open_bus +% register;
            const high: u16 = self.fetchNextByte();
            self.state.c_byte = low;
            self.state.c_addr = (high << 8) | low;
        }

        fn runCycle2IndirectX(self: *Self) void {
            _ = self.mem.read(self.state.c_byte);
            self.state.c_byte +%= self.reg.x;
        }

        fn runCycle2Relative(self: *Self) void {
            self.readNextByte();

            const cond = switch (self.state.op) {
                .op_bpl => !self.reg.getFlag("N"),
                .op_bmi => self.reg.getFlag("N"),
                .op_bvc => !self.reg.getFlag("V"),
                .op_bvs => self.reg.getFlag("V"),
                .op_bcc => !self.reg.getFlag("C"),
                .op_bcs => self.reg.getFlag("C"),
                .op_bne => !self.reg.getFlag("Z"),
                .op_beq => self.reg.getFlag("Z"),

                else => unreachable,
            };
            if (cond) {
                const new = @bitCast(u16, @bitCast(i16, self.reg.pc) +% @bitCast(i8, self.state.c_byte));
                flags.setMask(u16, &self.reg.pc, new, 0xff);
                self.state.c_addr = new;
            } else {
                self.reg.pc +%= 1;
                self.state.cycle = 0;
                const opcode = self.mem.open_bus;
                self.setStateFromOpcode(opcode);
            }
        }

        fn runCycle2ZpIndirect(self: *Self, register: u8) void {
            _ = self.mem.read(self.state.c_addr);
            flags.setMask(u16, &self.state.c_addr, self.state.c_addr +% register, 0xff);
        }

        fn runCycle3Special(self: *Self) void {
            switch (self.state.op) {
                .op_jmp => {
                    std.debug.assert(self.state.opcode == 0x6c);
                    self.state.c_byte = self.mem.read(self.state.c_addr);
                },
                .op_jsr => self.pushStack(@truncate(u8, self.reg.pc >> 8)),
                .op_pla => {
                    self.reg.a = self.readStack();
                    self.reg.setFlagsNZ(self.reg.a);
                    self.finishInstruction();
                },
                .op_plp => {
                    self.reg.p = self.readStack();
                    self.finishInstruction();
                },
                .op_rti => {
                    self.reg.p = self.readStack();
                    self.reg.s +%= 1;
                },
                .op_rts => {
                    flags.setMask(u16, &self.reg.pc, self.readStack(), 0xff);
                    self.reg.s +%= 1;
                },
                else => unreachable,
            }
        }

        fn runCycle3AbsoluteIndexed(self: *Self, register: u8) void {
            const low = self.state.c_byte;
            self.state.c_byte = self.mem.read(self.state.c_addr);
            if (register > low) {
                self.state.c_addr +%= 0x100;
            } else if (self.state.access == .read) {
                self.execOpcode();
            }
        }

        fn runCycle3IndirectY(self: *Self) void {
            const low = self.mem.open_bus +% self.reg.y;
            const high: u16 = self.mem.read(self.state.c_byte +% 1);
            self.state.c_byte = low;
            self.state.c_addr = (high << 8) | low;
        }

        fn runCycle3Relative(self: *Self) void {
            self.readNextByte();
            if (self.reg.pc != self.state.c_addr) {
                self.reg.pc = self.state.c_addr;
            } else {
                self.reg.pc +%= 1;
                self.state.cycle = 0;
                const opcode = self.mem.open_bus;
                self.setStateFromOpcode(opcode);
            }
        }

        fn runCycle4Special(self: *Self) void {
            switch (self.state.op) {
                .op_jmp => {
                    std.debug.assert(self.state.opcode == 0x6c);

                    flags.setMask(u16, &self.state.c_addr, self.state.c_addr +% 1, 0xff);

                    const low = self.state.c_byte;
                    const high: u16 = self.mem.read(self.state.c_addr);
                    self.reg.pc = (high << 8) | low;
                    self.finishInstruction();
                },
                .op_jsr => self.pushStack(@truncate(u8, self.reg.pc)),
                .op_rti => {
                    flags.setMask(u16, &self.reg.pc, self.readStack(), 0xff);
                    self.reg.s +%= 1;
                },
                .op_rts => flags.setMask(u16, &self.reg.pc, @as(u16, self.readStack()) << 8, 0xff00),
                else => unreachable,
            }
        }

        fn runCycle4IndirectX(self: *Self) void {
            const low = self.mem.open_bus;
            const high: u16 = self.mem.read(self.state.c_byte +% 1);
            self.state.c_addr = (high << 8) | low;
        }

        fn runCycle4IndirectY(self: *Self) void {
            const byte = self.mem.read(self.state.c_addr);
            if (self.reg.y > self.state.c_byte) {
                self.state.c_addr +%= 0x100;
            } else if (self.state.access == .read) {
                self.state.c_byte = byte;
                self.execOpcode();
            }
        }

        fn runCycle4Relative(self: *Self) void {
            self.state.cycle = 0;
            const opcode = self.fetchNextByte();
            self.setStateFromOpcode(opcode);
        }

        fn runCycle5Special(self: *Self) void {
            switch (self.state.op) {
                .op_jsr => {
                    const low = self.state.c_byte;
                    const high: u16 = self.mem.read(self.reg.pc);
                    self.reg.pc = (high << 8) | low;
                    self.finishInstruction();
                },
                .op_rti => {
                    flags.setMask(u16, &self.reg.pc, @as(u16, self.readStack()) << 8, 0xff00);
                    self.finishInstruction();
                },
                .op_rts => {
                    self.reg.pc +%= 1;
                    self.finishInstruction();
                },
                else => unreachable,
            }
        }

        /// Either return c_byte or, if it's an implied instruction, return A
        fn getByteMaybeAcc(self: Self) u8 {
            if (self.state.addressing == .implied) {
                return self.reg.a;
            } else {
                return self.state.c_byte;
            }
        }

        fn setByteMaybeAcc(self: *Self, val: u8) void {
            if (self.state.addressing == .implied) {
                self.reg.a = val;
            } else {
                self.mem.write(self.state.c_addr, val);
            }
        }

        fn execOpcode(self: *Self) void {
            const byte = self.state.c_byte;
            const addr = self.state.c_addr;

            switch (self.state.op) {
                .op_bpl, .op_bmi, .op_bvc, .op_bvs, .op_bcc, .op_bcs, .op_bne, .op_beq => unreachable,
                .op_jmp, .op_jsr => unreachable,

                .op_adc => self.execOpcodeAdc(false),

                .op_and => {
                    self.reg.a &= byte;
                    self.reg.setFlagsNZ(self.reg.a);
                },

                .op_asl => {
                    const val = self.getByteMaybeAcc();
                    const modified = val << 1;
                    self.setByteMaybeAcc(modified);
                    self.reg.setFlagsNZ(modified);
                    self.reg.setFlag("C", val & 0x80 != 0);
                },

                .op_bit => {
                    const val = self.reg.a & byte;
                    self.reg.setFlags("NVZ", (byte & 0xc0) | @as(u8, @boolToInt(val == 0)) << 1);
                },

                .op_clc => self.reg.setFlag("C", false),
                .op_cld => self.reg.setFlag("D", false),
                .op_cli => self.reg.setFlag("I", false),
                .op_clv => self.reg.setFlag("V", false),

                .op_cmp => self.execOpcodeCmp(self.reg.a),
                .op_cpx => self.execOpcodeCmp(self.reg.x),
                .op_cpy => self.execOpcodeCmp(self.reg.y),

                .op_dec => {
                    self.mem.write(addr, byte -% 1);
                    self.reg.setFlagsNZ(byte -% 1);
                },
                .op_dex => self.execOpcodeDecReg(&self.reg.x),
                .op_dey => self.execOpcodeDecReg(&self.reg.y),

                .op_eor => {
                    self.reg.a ^= byte;
                    self.reg.setFlagsNZ(self.reg.a);
                },

                .op_inc => {
                    self.mem.write(addr, byte +% 1);
                    self.reg.setFlagsNZ(byte +% 1);
                },
                .op_inx => self.execOpcodeIncReg(&self.reg.x),
                .op_iny => self.execOpcodeIncReg(&self.reg.y),

                .op_lda => self.execOpcodeLd(&self.reg.a),
                .op_ldx => self.execOpcodeLd(&self.reg.x),
                .op_ldy => self.execOpcodeLd(&self.reg.y),

                .op_lsr => {
                    const val = self.getByteMaybeAcc();
                    const modified = val >> 1;
                    self.setByteMaybeAcc(modified);
                    self.reg.setFlagsNZ(modified);
                    self.reg.setFlag("C", val & 1 != 0);
                },

                .op_nop => {},

                .op_ora => {
                    self.reg.a |= byte;
                    self.reg.setFlagsNZ(self.reg.a);
                },

                .op_rol => {
                    const val = self.getByteMaybeAcc();
                    const modified = (val << 1) | self.reg.getFlags("C");
                    self.setByteMaybeAcc(modified);
                    self.reg.setFlagsNZ(modified);
                    self.reg.setFlag("C", val & 0x80 != 0);
                },
                .op_ror => {
                    const val = self.getByteMaybeAcc();
                    const modified = (val >> 1) | (self.reg.getFlags("C") << 7);
                    self.setByteMaybeAcc(modified);
                    self.reg.setFlagsNZ(modified);
                    self.reg.setFlag("C", val & 1 != 0);
                },

                .op_sbc => self.execOpcodeAdc(true),

                .op_sec => self.reg.setFlag("C", true),
                .op_sed => self.reg.setFlag("D", true),
                .op_sei => self.reg.setFlag("I", true),

                .op_sta => self.mem.write(addr, self.reg.a),
                .op_stx => self.mem.write(addr, self.reg.x),
                .op_sty => self.mem.write(addr, self.reg.y),

                .op_tax => self.execOpcodeTransferReg(self.reg.a, &self.reg.x),
                .op_tay => self.execOpcodeTransferReg(self.reg.a, &self.reg.y),
                .op_tsx => self.execOpcodeTransferReg(self.reg.s, &self.reg.x),
                .op_txa => self.execOpcodeTransferReg(self.reg.x, &self.reg.a),
                .op_txs => self.execOpcodeTransferReg(self.reg.x, &self.reg.s),
                .op_tya => self.execOpcodeTransferReg(self.reg.y, &self.reg.a),
                else => unreachable,
            }

            self.finishInstruction();
        }

        fn execOpcodeAdc(self: *Self, subtract: bool) void {
            const val = if (subtract) ~self.state.c_byte else self.state.c_byte;
            const sum: u9 = @as(u9, self.reg.a) +
                @as(u9, val) +
                @as(u9, self.reg.getFlags("C"));
            const sum_u8: u8 = @truncate(u8, sum);

            const n_flag = sum_u8 & 0x80;
            const v_flag = (((self.reg.a ^ sum_u8) & (val ^ sum_u8)) & 0x80) >> 1;
            const z_flag = @as(u8, @boolToInt(sum_u8 == 0)) << 1;
            const c_flag = @truncate(u1, (sum & 0x100) >> 8);
            self.reg.setFlags("NVZC", n_flag | v_flag | z_flag | c_flag);

            self.reg.a = sum_u8;
        }

        fn execOpcodeCmp(self: *Self, reg: u8) void {
            self.reg.setFlagsNZ(reg -% self.state.c_byte);
            self.reg.setFlag("C", reg >= self.state.c_byte);
        }

        fn execOpcodeDecReg(self: *Self, reg: *u8) void {
            reg.* -%= 1;
            self.reg.setFlagsNZ(reg.*);
        }

        fn execOpcodeIncReg(self: *Self, reg: *u8) void {
            reg.* +%= 1;
            self.reg.setFlagsNZ(reg.*);
        }

        fn execOpcodeLd(self: *Self, reg: *u8) void {
            reg.* = self.state.c_byte;
            self.reg.setFlagsNZ(reg.*);
        }

        fn execOpcodeTransferReg(self: *Self, src: u8, dst: *u8) void {
            dst.* = src;
            if (dst != &self.reg.s) {
                self.reg.setFlagsNZ(src);
            }
        }

        fn logCycle(self: Self) void {
            const op_str = opToString(self.state.op);

            const cycle = if (self.state.cycle == 15) -1 else @intCast(i5, self.state.cycle);
            std.debug.print("Ct: {}; C: {: >2}; {s}; PC: ${x:0>4}; Bus: ${x:0>2}; " ++
                "A: ${x:0>2}; X: ${x:0>2}; Y: ${x:0>2}; P: %{b:0>8}; S: ${x:0>2}\n", .{
                self.cycles,
                cycle,
                op_str,
                self.reg.pc,
                self.mem.open_bus,
                self.reg.a,
                self.reg.x,
                self.reg.y,
                self.reg.p,
                self.reg.s,
            });
        }
    };
}

pub fn Memory(comptime config: Config) type {
    return struct {
        const Self = @This();

        cart: *Cart(config),
        ppu: *Ppu(config),
        apu: *Apu(config),
        controller: *Controller(config.method),
        ram: [0x800]u8,

        open_bus: u8,

        // TODO: implement non-zero pattern?
        pub fn zeroes(
            cart: *Cart(config),
            ppu: *Ppu(config),
            apu: *Apu(config),
            controller: *Controller(config.method),
        ) Self {
            return Self{
                .cart = cart,
                .ppu = ppu,
                .apu = apu,
                .controller = controller,
                .ram = [_]u8{0} ** 0x800,
                .open_bus = 0,
            };
        }

        pub fn peek(self: Self, addr: u16) u8 {
            switch (addr) {
                0x0000...0x1fff => return self.ram[addr & 0x7ff],
                0x2000...0x3fff => return self.ppu.reg.peek(@truncate(u3, addr)),
                0x4020...0xffff => return self.cart.peekPrg(addr) orelse 0,
                else => return 0,
            }
        }

        pub fn read(self: *Self, addr: u16) u8 {
            self.open_bus = switch (addr) {
                0x0000...0x1fff => self.ram[addr & 0x7ff],
                0x2000...0x3fff => self.ppu.reg.read(@truncate(u3, addr)),
                0x4000...0x4013, 0x4015, 0x4017 => self.apu.read(@truncate(u5, addr)),
                0x4014 => self.ppu.reg.io_bus,
                0x4016 => self.controller.getNextButton(),
                0x4018...0x401f => return self.open_bus,
                0x4020...0xffff => self.cart.readPrg(addr) orelse self.open_bus,
            };
            return self.open_bus;
        }

        pub fn sneak(self: *Self, addr: u16, val: u8) void {
            switch (addr) {
                0x0000...0x1fff => self.ram[addr & 0x7ff] = val,
                else => {},
            }
        }

        pub fn write(self: *Self, addr: u16, val: u8) void {
            self.open_bus = val;
            switch (addr) {
                0x0000...0x1fff => self.ram[addr & 0x7ff] = val,
                0x2000...0x3fff => self.ppu.reg.write(@truncate(u3, addr), val),
                0x4000...0x4013, 0x4015, 0x4017 => self.apu.write(@truncate(u5, addr), val),
                0x4014 => @fieldParentPtr(Cpu(config), "mem", self).dma(val),
                0x4016 => if (val & 1 == 1) {
                    self.controller.strobe();
                },
                0x4018...0x401f => {},
                0x4020...0xffff => self.cart.writePrg(addr, val),
            }
        }
    };
}
