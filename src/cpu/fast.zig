const std = @import("std");
const Allocator = std.mem.Allocator;

const common = @import("common.zig");

const instruction_ = @import("../instruction.zig");
const Op = instruction_.Op;
const Addressing = instruction_.Addressing;
const Instruction = instruction_.Instruction;
const opToString = instruction_.opToString;

const console_ = @import("../console.zig");
const Config = console_.Config;
const Console = console_.Console;

const Cart = @import("../cart.zig").Cart;
const Ppu = @import("../ppu.zig").Ppu;
const Apu = @import("../apu.zig").Apu;
const Controller = @import("../controller.zig").Controller;

pub fn Cpu(comptime config: Config) type {
    return struct {
        const Self = @This();

        reg: common.Registers,
        mem: Memory(config),
        ppu: *Ppu(config),
        apu: *Apu(config),
        cycles: usize = 0,

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
            self.reg.pc = self.mem.readWord(0xfffc);
            std.log.debug("PC set to {x:0>4}", .{self.reg.pc});
        }

        pub fn setIrqSource(self: *Self, comptime _: []const u8) void {
            if (self.reg.getFlag("I")) {
                return;
            }
            self.pushStack(@truncate(u8, self.reg.pc >> 8));
            self.pushStack(@truncate(u8, self.reg.pc));
            self.pushStack(self.reg.p | 0b0010_0000);
            self.reg.setFlag("I", true);
            self.reg.pc = self.mem.readWord(0xfffe);
        }

        pub fn clearIrqSource(_: *Self, comptime _: []const u8) void {}

        pub fn setNmi(self: *Self) void {
            self.pushStack(@truncate(u8, self.reg.pc >> 8));
            self.pushStack(@truncate(u8, self.reg.pc));
            self.pushStack(self.reg.p | 0b0010_0000);
            self.reg.setFlag("I", true);
            self.reg.pc = self.mem.readWord(0xfffa);
        }

        fn dma(self: *Self, addr_high: u8) void {
            const oam_addr = self.ppu.reg.oam_addr;
            var i: usize = 0;
            while (i < 256) : (i += 1) {
                const oam_i: u8 = oam_addr +% @truncate(u8, i);
                self.ppu.mem.oam[oam_i] = self.mem.read((@as(u16, addr_high) << 8) | @truncate(u8, i));

                self.apu.runCycle();
                self.ppu.runCycle();
                self.ppu.runCycle();
                self.ppu.runCycle();
                self.apu.runCycle();
                self.ppu.runCycle();
                self.ppu.runCycle();
                self.ppu.runCycle();
            }
        }

        fn pushStack(self: *Self, val: u8) void {
            self.mem.write(@as(u9, self.reg.s) | 0x100, val);
            self.reg.s -%= 1;
        }

        fn popStack(self: *Self) u8 {
            self.reg.s +%= 1;
            return self.mem.read(@as(u9, self.reg.s) | 0x100);
        }

        fn branchRelative(self: *Self, condition: bool, jump: u8) void {
            if (condition) {
                const prev_pc = self.reg.pc;
                self.reg.pc = @bitCast(u16, @bitCast(i16, self.reg.pc) +% @bitCast(i8, jump));
                self.cycles += @as(usize, 1) + @boolToInt(self.reg.pc & 0xff00 != prev_pc & 0xff00);
            }
        }

        const ValueReference = union(enum) {
            none,
            register: *u8,
            memory: u16,

            fn peek(ref: @This(), cpu: Cpu(config)) u8 {
                return switch (ref) {
                    .none => unreachable,
                    .register => |ptr| ptr.*,
                    .memory => |addr| cpu.mem.peek(addr),
                };
            }

            fn read(ref: @This(), cpu: *Cpu(config)) u8 {
                return switch (ref) {
                    .none => unreachable,
                    .register => |ptr| ptr.*,
                    .memory => |addr| cpu.mem.read(addr),
                };
            }

            fn write(ref: @This(), cpu: *Cpu(config), val: u8) void {
                switch (ref) {
                    .none => unreachable,
                    .register => |ptr| ptr.* = val,
                    .memory => |addr| cpu.mem.write(addr, val),
                }
            }
        };

        /// Runs an instruction
        pub fn runStep(self: *Self) void {
            const opcode = self.mem.read(self.reg.pc);
            const instruction = Instruction(.fast).decode(opcode);

            self.reg.pc +%= 1;
            const value: ValueReference = blk: {
                switch (instruction.addressing) {
                    .accumulator => break :blk ValueReference{ .register = &self.reg.a },
                    .absolute => {
                        break :blk ValueReference{ .memory = self.mem.readWord(self.reg.pc) };
                    },
                    .absolute_x => {
                        const val = self.mem.readWord(self.reg.pc);
                        self.cycles += @boolToInt(instruction.var_cycles and (val +% self.reg.x) & 0xff < val & 0xff);
                        break :blk ValueReference{ .memory = val +% self.reg.x };
                    },
                    .absolute_y => {
                        const val = self.mem.readWord(self.reg.pc);
                        self.cycles += @boolToInt(instruction.var_cycles and (val +% self.reg.y) & 0xff < val & 0xff);
                        break :blk ValueReference{ .memory = val +% self.reg.y };
                    },
                    .immediate => break :blk ValueReference{ .memory = self.reg.pc },
                    .implied => break :blk .none,
                    .indirect => {
                        const addr_low = self.mem.read(self.reg.pc);
                        const addr_high = @as(u16, self.mem.read(self.reg.pc +% 1)) << 8;

                        const val_low = self.mem.read(addr_high | addr_low);
                        const val_high = self.mem.read(addr_high | (addr_low +% 1));
                        break :blk ValueReference{ .memory = (@as(u16, val_high) << 8) | val_low };
                    },
                    .indirect_x => {
                        const zero_page = self.mem.read(self.reg.pc);

                        const val_low = self.mem.read(zero_page +% self.reg.x);
                        const val_high = self.mem.read(zero_page +% self.reg.x +% 1);
                        break :blk ValueReference{ .memory = (@as(u16, val_high) << 8) | val_low };
                    },
                    .indirect_y => {
                        const zero_page = self.mem.read(self.reg.pc);

                        const val_low = self.mem.read(zero_page);
                        const val_high = self.mem.read(zero_page +% 1);

                        self.cycles += @boolToInt(instruction.var_cycles and (val_low +% self.reg.y) < val_low);
                        break :blk ValueReference{ .memory = ((@as(u16, val_high) << 8) | val_low) +% self.reg.y };
                    },
                    .relative => break :blk ValueReference{ .memory = self.reg.pc },
                    .zero_page => {
                        const zero_page = self.mem.read(self.reg.pc);
                        break :blk ValueReference{ .memory = zero_page };
                    },
                    .zero_page_x => {
                        const zero_page = self.mem.read(self.reg.pc);
                        break :blk ValueReference{ .memory = zero_page +% self.reg.x };
                    },
                    .zero_page_y => {
                        const zero_page = self.mem.read(self.reg.pc);
                        break :blk ValueReference{ .memory = zero_page +% self.reg.y };
                    },
                }
            };

            if (@import("build_options").log_step) {
                self.logInstruction(instruction, value);
            }

            switch (instruction.op) {
                .op_ill => {},
                .op_adc => {
                    const original: u8 = value.read(self);
                    const sum: u9 = @as(u9, self.reg.a) +
                        @as(u9, original) +
                        @as(u9, self.reg.getFlags("C"));
                    const sum_u8: u8 = @truncate(u8, sum);

                    const n_flag = sum_u8 & 0x80;
                    const v_flag = (((self.reg.a ^ sum_u8) & (original ^ sum_u8)) & 0x80) >> 1;
                    const z_flag = @as(u8, @boolToInt(sum_u8 == 0)) << 1;
                    const c_flag = @truncate(u8, (sum & 0x100) >> 8);
                    self.reg.setFlags("NVZC", n_flag | v_flag | z_flag | c_flag);

                    self.reg.a = sum_u8;
                },
                .op_and => {
                    self.reg.a &= value.read(self);
                    self.reg.setFlagsNZ(self.reg.a);
                },
                .op_asl => {
                    const val = value.read(self);
                    const new = val << 1;

                    value.write(self, new);
                    self.reg.setFlagsNZ(new);
                    self.reg.setFlag("C", (val & 0x80) != 0);
                },
                .op_bpl => self.branchRelative(!self.reg.getFlag("N"), value.read(self)),
                .op_bmi => self.branchRelative(self.reg.getFlag("N"), value.read(self)),
                .op_bvc => self.branchRelative(!self.reg.getFlag("V"), value.read(self)),
                .op_bvs => self.branchRelative(self.reg.getFlag("V"), value.read(self)),
                .op_bcc => self.branchRelative(!self.reg.getFlag("C"), value.read(self)),
                .op_bcs => self.branchRelative(self.reg.getFlag("C"), value.read(self)),
                .op_bne => self.branchRelative(!self.reg.getFlag("Z"), value.read(self)),
                .op_beq => self.branchRelative(self.reg.getFlag("Z"), value.read(self)),
                .op_bit => {
                    const mem = value.read(self);
                    const val = self.reg.a & mem;
                    self.reg.setFlags("NVZ", (mem & 0xc0) | @as(u8, @boolToInt(val == 0)) << 1);
                },
                .op_brk => {
                    var push_sp = self.reg.pc +% 1;
                    self.pushStack(@truncate(u8, push_sp >> 8));
                    self.pushStack(@truncate(u8, push_sp));
                    self.pushStack(self.reg.p | 0b0011_0000);
                    self.reg.pc = self.mem.readWord(0xfffe);
                },
                .op_clc => self.reg.setFlag("C", false),
                .op_cld => self.reg.setFlag("D", false),
                .op_cli => self.reg.setFlag("I", false),
                .op_clv => self.reg.setFlag("V", false),
                .op_cmp => {
                    const val = value.read(self);
                    self.reg.setFlagsNZ(self.reg.a -% val);
                    self.reg.setFlag("C", self.reg.a >= val);
                },
                .op_cpx => {
                    const val = value.read(self);
                    self.reg.setFlagsNZ(self.reg.x -% val);
                    self.reg.setFlag("C", self.reg.x >= val);
                },
                .op_cpy => {
                    const val = value.read(self);
                    self.reg.setFlagsNZ(self.reg.y -% val);
                    self.reg.setFlag("C", self.reg.y >= val);
                },
                .op_dec => {
                    const val = value.read(self) -% 1;
                    value.write(self, val);
                    self.reg.setFlagsNZ(val);
                },
                .op_dex => {
                    self.reg.x -%= 1;
                    self.reg.setFlagsNZ(self.reg.x);
                },
                .op_dey => {
                    self.reg.y -%= 1;
                    self.reg.setFlagsNZ(self.reg.y);
                },
                .op_eor => {
                    self.reg.a ^= value.read(self);
                    self.reg.setFlagsNZ(self.reg.a);
                },
                .op_inc => {
                    const val = value.read(self) +% 1;
                    value.write(self, val);
                    self.reg.setFlagsNZ(val);
                },
                .op_inx => {
                    self.reg.x +%= 1;
                    self.reg.setFlagsNZ(self.reg.x);
                },
                .op_iny => {
                    self.reg.y +%= 1;
                    self.reg.setFlagsNZ(self.reg.y);
                },
                .op_jmp => self.reg.pc = value.memory -% 2,
                .op_jsr => {
                    var push_sp = self.reg.pc +% 1;
                    self.pushStack(@truncate(u8, push_sp >> 8));
                    self.pushStack(@truncate(u8, push_sp));
                    self.reg.pc = value.memory -% 2;
                },
                .op_lda => {
                    self.reg.a = value.read(self);
                    self.reg.setFlagsNZ(self.reg.a);
                },
                .op_ldx => {
                    self.reg.x = value.read(self);
                    self.reg.setFlagsNZ(self.reg.x);
                },
                .op_ldy => {
                    self.reg.y = value.read(self);
                    self.reg.setFlagsNZ(self.reg.y);
                },
                .op_lsr => {
                    const val = value.read(self);
                    const new = val >> 1;

                    value.write(self, new);
                    self.reg.setFlagsNZ(new);
                    self.reg.setFlags("C", val & 1);
                },
                .op_nop => {},
                .op_ora => {
                    self.reg.a |= value.read(self);
                    self.reg.setFlagsNZ(self.reg.a);
                },
                .op_pha => self.pushStack(self.reg.a),
                .op_php => self.pushStack(self.reg.p | 0b0011_0000),
                .op_pla => {
                    self.reg.a = self.popStack();
                    self.reg.setFlagsNZ(self.reg.a);
                },
                .op_plp => self.reg.p = self.popStack(),
                .op_rol => {
                    const val = value.read(self);
                    const new = (val << 1) | self.reg.getFlags("C");

                    value.write(self, new);
                    self.reg.setFlagsNZ(new);
                    self.reg.setFlags("C", (val & 0x80) >> 7);
                },
                .op_ror => {
                    const val = value.read(self);
                    const new = (val >> 1) | (self.reg.getFlags("C") << 7);

                    value.write(self, new);
                    self.reg.setFlagsNZ(new);
                    self.reg.setFlags("C", val & 1);
                },
                .op_rti => {
                    self.reg.p = self.popStack();
                    const low = self.popStack();
                    const high = @as(u16, self.popStack());
                    self.reg.pc = (high << 8) | low;
                },
                .op_rts => {
                    const low = self.popStack();
                    const high = @as(u16, self.popStack());
                    self.reg.pc = ((high << 8) | low) +% 1;
                },
                .op_sbc => {
                    const original: u8 = value.read(self);
                    const dif: u9 = @as(u9, self.reg.a) -%
                        @as(u9, original) -%
                        @as(u9, @boolToInt(!self.reg.getFlag("C")));
                    const dif_u8: u8 = @truncate(u8, dif);

                    const n_flag = dif_u8 & 0x80;
                    const v_flag = (((self.reg.a ^ dif_u8) & (~original ^ dif_u8)) & 0x80) >> 1;
                    const z_flag = @as(u8, @boolToInt(dif_u8 == 0)) << 1;
                    const c_flag = ~@truncate(u1, (dif & 0x100) >> 8);
                    self.reg.setFlags("NVZC", n_flag | v_flag | z_flag | c_flag);

                    self.reg.a = dif_u8;
                },
                .op_sec => self.reg.setFlag("C", true),
                .op_sed => self.reg.setFlag("D", true),
                .op_sei => self.reg.setFlag("I", true),
                .op_sta => value.write(self, self.reg.a),
                .op_stx => value.write(self, self.reg.x),
                .op_sty => value.write(self, self.reg.y),
                .op_tax => {
                    self.reg.x = self.reg.a;
                    self.reg.setFlagsNZ(self.reg.x);
                },
                .op_tay => {
                    self.reg.y = self.reg.a;
                    self.reg.setFlagsNZ(self.reg.y);
                },
                .op_tsx => {
                    self.reg.x = self.reg.s;
                    self.reg.setFlagsNZ(self.reg.x);
                },
                .op_txa => {
                    self.reg.a = self.reg.x;
                    self.reg.setFlagsNZ(self.reg.a);
                },
                .op_txs => self.reg.s = self.reg.x,
                .op_tya => {
                    self.reg.a = self.reg.y;
                    self.reg.setFlagsNZ(self.reg.a);
                },
            }

            self.reg.pc +%= instruction.addressing.op_size() - 1;
            self.cycles += instruction.cycles;

            var i: usize = 0;
            while (i < @as(usize, instruction.cycles)) : (i += 1) {
                common.cpuCycled(self);
            }
        }

        fn logInstruction(self: Self, instruction: Instruction(.fast), value: ValueReference) void {
            const op_str = opToString(instruction.op);

            const opcode = self.mem.peek(self.reg.pc -% 1);
            const low = self.mem.peek(self.reg.pc);
            const high = self.mem.peek(self.reg.pc +% 1);
            const address = (@as(u16, high) << 8) | low;

            std.debug.print("Cycles: {} ", .{self.cycles});
            std.debug.print("A: {x:0>2} X: {x:0>2} Y: {x:0>2} P: {x:0>2} S: {x:0>2} PC: {x:0>4}\t", .{
                self.reg.a,
                self.reg.x,
                self.reg.y,
                self.reg.p | 0x20,
                self.reg.s,
                self.reg.pc -% 1,
            });
            std.debug.print("{x:0>2} {x:0>2} {x:0>2}\t{s} ", .{ opcode, low, high, op_str });

            switch (instruction.addressing) {
                .accumulator => std.debug.print("A", .{}),
                .absolute => {
                    std.debug.print("${x:0>4}    \t; ${0x:0>4} = #${x:0>2}", .{ value.memory, value.peek(self) });
                },
                .absolute_x => {
                    std.debug.print("${x:0>4},x  \t; ${0x:0>4} = #${x:0>2}\tx = #${x:0>2}", .{
                        value.memory,
                        value.peek(self),
                        self.reg.x,
                    });
                },
                .absolute_y => {
                    std.debug.print("${x:0>4},y  \t; ${0x:0>4} = #${x:0>2}\ty = #${x:0>2}", .{
                        value.memory,
                        value.peek(self),
                        self.reg.y,
                    });
                },
                .immediate => std.debug.print("#${x:0>2}", .{low}),
                .implied => {},
                .indirect => {
                    std.debug.print("(${x:0>4})  \t; (${0x:0>4}) = ${x:0>4}", .{ address, value.memory });
                },
                .indirect_x => {
                    std.debug.print("(${x:0>2},x)\t; (${0x:0>4},{x:0>2}) = ${x:0>4} = #${x:0>2}", .{
                        low,
                        self.reg.x,
                        value.memory,
                        value.peek(self),
                    });
                },
                .indirect_y => {
                    std.debug.print("(${x:0>2}),y\t; (${0x:0>4}),{x:0>2} = ${x:0>4} = #${x:0>2}", .{
                        low,
                        self.reg.y,
                        value.memory,
                        value.peek(self),
                    });
                },
                .relative => {
                    const val = value.peek(self);
                    const new_pc = @bitCast(u16, @bitCast(i16, self.reg.pc) +% @bitCast(i8, val) +% 1);
                    std.debug.print("${x:0>2}      \t; PC ?= ${x:0>4}", .{ val, new_pc });
                },
                .zero_page => {
                    std.debug.print("${x:0>2}      \t; ${0x:0>2} = #${x:0>2}", .{ value.memory, value.peek(self) });
                },
                .zero_page_x => {
                    std.debug.print("${x:0>2},x    \t; ${0x:0>2} = #${x:0>2}", .{ value.memory, value.peek(self) });
                },
                .zero_page_y => {
                    std.debug.print("${x:0>2},y    \t; ${0x:0>2} = #${x:0>2}", .{ value.memory, value.peek(self) });
                },
            }

            std.debug.print("\n", .{});
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
            };
        }

        pub fn peek(self: Self, addr: u16) u8 {
            switch (addr) {
                0x0000...0x1fff => return self.ram[addr & 0x7ff],
                0x2000...0x3fff => return self.ppu.reg.peek(@truncate(u3, addr)),
                0x8000...0xffff => return self.cart.peekPrg(addr) orelse 0,
                else => return 0,
            }
        }

        pub fn read(self: Self, addr: u16) u8 {
            switch (addr) {
                0x0000...0x1fff => return self.ram[addr & 0x7ff],
                0x2000...0x3fff => return self.ppu.reg.read(@truncate(u3, addr)),
                0x4000...0x4013, 0x4015, 0x4017 => return self.apu.read(@truncate(u5, addr)),
                0x4016 => return self.controller.getNextButton(),
                0x4020...0xffff => return self.cart.readPrg(addr) orelse 0,
                else => {
                    //std.log.err("CPU: Unimplemented read memory address ({x:0>4})", .{addr});
                    return 0;
                },
            }
        }

        pub fn readWord(self: Self, addr: u16) u16 {
            var low = self.read(addr);
            return (@as(u16, self.read(addr +% 1)) << 8) | low;
        }

        pub fn write(self: *Self, addr: u16, val: u8) void {
            switch (addr) {
                0x0000...0x1fff => self.ram[addr & 0x7ff] = val,
                0x2000...0x3fff => self.ppu.reg.write(@truncate(u3, addr), val),
                0x4000...0x4013, 0x4015, 0x4017 => self.apu.write(@truncate(u5, addr), val),
                0x4014 => @fieldParentPtr(Cpu(config), "mem", self).dma(val),
                0x4016 => if (val & 1 == 1) {
                    self.controller.strobe();
                },
                0x4020...0xffff => return self.cart.writePrg(addr, val),
                else => {
                    //std.log.err("CPU: Unimplemented write memory address ({x:0>4})", .{addr});
                },
            }
        }
    };
}
