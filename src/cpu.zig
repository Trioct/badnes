const std = @import("std");
const Allocator = std.mem.Allocator;

const instruction_ = @import("instruction.zig");
const Op = instruction_.Op;
const Addressing = instruction_.Addressing;
const Instruction = instruction_.Instruction;

const Precision = @import("main.zig").Precision;
const Cart = @import("cart.zig").Cart;
const Ppu = @import("ppu.zig").Ppu;
const Controller = @import("controller.zig").Controller;

const flags_ = @import("flags.zig");
const CreateFlags = flags_.CreateFlags;
const FieldFlagsDef = flags_.FieldFlagsDef;

pub const Cpu = struct {
    reg: Registers,
    mem: Memory,
    ppu: *Ppu(.Accurate),
    cycles: usize = 0,

    pub const Registers = struct {
        pc: u16,
        s: u8,

        a: u8,
        x: u8,
        y: u8,
        p: u8,

        const ff_masks = CreateFlags(Registers, ([_]FieldFlagsDef{
            .{ .field = "p", .flags = "NV??DIZC" },
        })[0..]){};

        /// Convenient for testing
        pub fn zeroes() Registers {
            return std.mem.zeroes(Registers);
        }

        /// Real world observed values
        pub fn startup() Registers {
            return Registers{
                .pc = 0x00,
                .s = 0xfd,

                .a = 0x00,
                .x = 0x00,
                .y = 0x00,
                .p = 0x34,
            };
        }

        pub fn getFlag(self: Registers, comptime flags: []const u8) bool {
            return ff_masks.getFlag(self, .{ .flags = flags });
        }

        pub fn getFlags(self: Registers, comptime flags: []const u8) u8 {
            return ff_masks.getFlags(self, .{ .flags = flags });
        }

        pub fn setFlag(self: *Registers, comptime flags: []const u8, val: bool) void {
            return ff_masks.setFlag(self, .{ .flags = flags }, val);
        }

        pub fn setFlags(self: *Registers, comptime flags: []const u8, val: u8) void {
            return ff_masks.setFlags(self, .{ .flags = flags }, val);
        }

        pub fn setFlagsNZ(self: *Registers, val: u8) void {
            self.setFlags("NZ", (val & 0x80) | @as(u8, @boolToInt(val == 0)) << 1);
        }

        fn FieldType(comptime field: []const u8) type {
            std.debug.assert(@hasField(Registers, field) or Registers.hasFlags(field));
            if (std.mem.eql(u8, field, "pc")) {
                return u16;
            } else {
                return u8;
            }
        }

        pub fn get(self: Registers, comptime field: []const u8) FieldType(field) {
            if (@hasField(Registers, field)) {
                return @field(self, field);
            } else if (Registers.hasFlags(field)) {
                return self.getFlags(field);
            } else {
                @compileError("Unknown field for registers");
            }
        }

        pub fn set(self: *Registers, comptime field: []const u8, val: u8) void {
            if (@hasField(Registers, field)) {
                @field(self, field) = val;
            } else if (Registers.hasFlags(field)) {
                return self.setFlags(field, val);
            } else {
                @compileError("Unknown field for registers");
            }
        }
    };

    pub const Memory = struct {
        cart: *Cart,
        ppu: *Ppu(.Accurate),
        controller: *Controller,
        ram: [0x800]u8,

        // TODO: implement non-zero pattern?
        pub fn zeroes(cart: *Cart, ppu: *Ppu(.Accurate), controller: *Controller) Memory {
            return Memory{
                .cart = cart,
                .ppu = ppu,
                .controller = controller,
                .ram = [_]u8{0} ** 0x800,
            };
        }

        pub fn peek(self: Memory, addr: u16) u8 {
            switch (addr) {
                0x0000...0x1fff => return self.ram[addr & 0x7ff],
                0x2000...0x3fff => return self.ppu.reg.peek(@truncate(u3, addr)),
                0x8000...0xffff => return self.cart.peekPrg(addr & 0x7fff),
                else => return 0,
            }
        }

        pub fn read(self: Memory, addr: u16) u8 {
            switch (addr) {
                0x0000...0x1fff => return self.ram[addr & 0x7ff],
                0x2000...0x3fff => return self.ppu.reg.read(@truncate(u3, addr)),
                0x8000...0xffff => return self.cart.readPrg(addr & 0x7fff),
                0x4016 => return self.controller.getNextButton(),
                else => {
                    //std.log.err("Unimplemented read memory address ({x:0>4})", .{addr});
                    return 0;
                },
            }
        }

        pub fn readWord(self: Memory, addr: u16) u16 {
            var low = self.read(addr);
            return (@as(u16, self.read(addr +% 1)) << 8) | low;
        }

        pub fn write(self: *Memory, addr: u16, val: u8) void {
            switch (addr) {
                0x0000...0x1fff => self.ram[addr & 0x7ff] = val,
                0x2000...0x3fff => self.ppu.reg.write(@truncate(u3, addr), val),
                0x4014 => @fieldParentPtr(Cpu, "mem", self).dma(val),
                0x4016 => if (val & 1 == 1) {
                    self.controller.strobe();
                },
                else => {
                    //std.log.err("Unimplemented write memory address ({x:0>4})", .{addr});
                },
            }
        }
    };

    pub fn init(cart: *Cart, ppu: *Ppu(.Accurate), controller: *Controller) Cpu {
        return Cpu{
            .reg = Registers.startup(),
            .mem = Memory.zeroes(cart, ppu, controller),
            .ppu = ppu,
        };
    }

    pub fn deinit(self: Cpu) void {
        _ = self;
    }

    pub fn reset(self: *Cpu) void {
        self.reg.pc = self.mem.readWord(0xfffc);
        //self.reg.pc = 0xc000;
        std.log.debug("PC set to {x:0>4}", .{self.reg.pc});
    }

    pub fn nmi(self: *Cpu) void {
        self.pushStack(@truncate(u8, self.reg.pc >> 8));
        self.pushStack(@truncate(u8, self.reg.pc));
        self.pushStack(self.reg.p | 0b0010_0000);
        self.reg.setFlag("I", true);
        self.reg.pc = self.mem.readWord(0xfffa);
    }

    pub fn dma(self: *Cpu, addr_high: u8) void {
        var i: usize = 0;
        while (i < 256) : (i += 1) {
            // TODO: just to get compiling
            if (@TypeOf(self.ppu.*) == Ppu(.Fast)) {
                self.ppu.mem.oam[i] = self.mem.read((@as(u16, addr_high) << 8) | @truncate(u8, i));
            } else {
                self.ppu.oam.primary[i] = self.mem.read((@as(u16, addr_high) << 8) | @truncate(u8, i));
            }
            self.ppu.runCycle();
            self.ppu.runCycle();
        }
    }

    pub fn pushStack(self: *Cpu, val: u8) void {
        self.mem.write(@as(u9, self.reg.s) | 0x100, val);
        self.reg.s -%= 1;
    }

    pub fn popStack(self: *Cpu) u8 {
        self.reg.s +%= 1;
        return self.mem.read(@as(u9, self.reg.s) | 0x100);
    }

    pub fn branchRelative(self: *Cpu, condition: bool, jump: u8) void {
        if (condition) {
            const prev_pc = self.reg.pc;
            self.reg.pc = @bitCast(u16, @bitCast(i16, self.reg.pc) +% @bitCast(i8, jump));
            self.cycles += @as(usize, 1) + @boolToInt(self.reg.pc & 0xff00 != prev_pc & 0xff00);
        }
    }

    const ValueReference = union(enum) {
        None,
        Register: *u8,
        Memory: u16,

        fn peek(ref: @This(), cpu: Cpu) u8 {
            return switch (ref) {
                .None => unreachable,
                .Register => |ptr| ptr.*,
                .Memory => |addr| cpu.mem.peek(addr),
            };
        }

        fn read(ref: @This(), cpu: *Cpu) u8 {
            return switch (ref) {
                .None => unreachable,
                .Register => |ptr| ptr.*,
                .Memory => |addr| cpu.mem.read(addr),
            };
        }

        fn write(ref: @This(), cpu: *Cpu, val: u8) void {
            switch (ref) {
                .None => unreachable,
                .Register => |ptr| ptr.* = val,
                .Memory => |addr| cpu.mem.write(addr, val),
            }
        }
    };

    pub fn runInstruction(self: *Cpu, comptime precision: Precision) void {
        const opcode = self.mem.read(self.reg.pc);
        const instruction = Instruction(precision).decode(opcode);

        self.reg.pc +%= 1;
        const value: ValueReference = blk: {
            switch (instruction.addressing) {
                .Accumulator => break :blk ValueReference{ .Register = &self.reg.a },
                .Absolute => {
                    break :blk ValueReference{ .Memory = self.mem.readWord(self.reg.pc) };
                },
                .AbsoluteX => {
                    const val = self.mem.readWord(self.reg.pc);
                    self.cycles += @boolToInt(instruction.var_cycles and (val +% self.reg.x) & 0xff < val & 0xff);
                    break :blk ValueReference{ .Memory = val +% self.reg.x };
                },
                .AbsoluteY => {
                    const val = self.mem.readWord(self.reg.pc);
                    self.cycles += @boolToInt(instruction.var_cycles and (val +% self.reg.y) & 0xff < val & 0xff);
                    break :blk ValueReference{ .Memory = val +% self.reg.y };
                },
                .Immediate => break :blk ValueReference{ .Memory = self.reg.pc },
                .Implied => break :blk .None,
                .Indirect => {
                    const addr_low = self.mem.read(self.reg.pc);
                    const addr_high = @as(u16, self.mem.read(self.reg.pc +% 1)) << 8;

                    const val_low = self.mem.read(addr_high | addr_low);
                    const val_high = self.mem.read(addr_high | (addr_low +% 1));
                    break :blk ValueReference{ .Memory = (@as(u16, val_high) << 8) | val_low };
                },
                .IndirectX => {
                    const zero_page = self.mem.read(self.reg.pc);

                    const val_low = self.mem.read(zero_page +% self.reg.x);
                    const val_high = self.mem.read(zero_page +% self.reg.x +% 1);
                    break :blk ValueReference{ .Memory = (@as(u16, val_high) << 8) | val_low };
                },
                .IndirectY => {
                    const zero_page = self.mem.read(self.reg.pc);

                    const val_low = self.mem.read(zero_page);
                    const val_high = self.mem.read(zero_page +% 1);

                    self.cycles += @boolToInt(instruction.var_cycles and (val_low +% self.reg.y) < val_low);
                    break :blk ValueReference{ .Memory = ((@as(u16, val_high) << 8) | val_low) +% self.reg.y };
                },
                .Relative => break :blk ValueReference{ .Memory = self.reg.pc },
                .ZeroPage => {
                    const zero_page = self.mem.read(self.reg.pc);
                    break :blk ValueReference{ .Memory = zero_page };
                },
                .ZeroPageX => {
                    const zero_page = self.mem.read(self.reg.pc);
                    break :blk ValueReference{ .Memory = zero_page +% self.reg.x };
                },
                .ZeroPageY => {
                    const zero_page = self.mem.read(self.reg.pc);
                    break :blk ValueReference{ .Memory = zero_page +% self.reg.y };
                },
            }
        };

        //self.logInstruction(instruction, value);

        switch (instruction.op) {
            .OpIll => {},
            .OpAdc => {
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
            .OpAnd => {
                self.reg.a &= value.read(self);
                self.reg.setFlagsNZ(self.reg.a);
            },
            .OpAsl => {
                const val = value.read(self);
                const new = val << 1;

                value.write(self, new);
                self.reg.setFlagsNZ(new);
                self.reg.setFlag("C", (val & 0x80) != 0);
            },
            .OpBpl => self.branchRelative(!self.reg.getFlag("N"), value.read(self)),
            .OpBmi => self.branchRelative(self.reg.getFlag("N"), value.read(self)),
            .OpBvc => self.branchRelative(!self.reg.getFlag("V"), value.read(self)),
            .OpBvs => self.branchRelative(self.reg.getFlag("V"), value.read(self)),
            .OpBcc => self.branchRelative(!self.reg.getFlag("C"), value.read(self)),
            .OpBcs => self.branchRelative(self.reg.getFlag("C"), value.read(self)),
            .OpBne => self.branchRelative(!self.reg.getFlag("Z"), value.read(self)),
            .OpBeq => self.branchRelative(self.reg.getFlag("Z"), value.read(self)),
            .OpBit => {
                const mem = value.read(self);
                const val = self.reg.a & mem;
                self.reg.setFlags("NVZ", (mem & 0xc0) | @as(u8, @boolToInt(val == 0)) << 1);
            },
            .OpBrk => {
                var push_sp = self.reg.pc +% 1;
                self.pushStack(@truncate(u8, push_sp >> 8));
                self.pushStack(@truncate(u8, push_sp));
                self.pushStack(self.reg.p | 0b0011_0000);
                self.reg.pc = self.mem.readWord(0xfffe);
            },
            .OpClc => self.reg.setFlag("C", false),
            .OpCld => self.reg.setFlag("D", false),
            .OpCli => self.reg.setFlag("I", false),
            .OpClv => self.reg.setFlag("V", false),
            .OpCmp => {
                const val = value.read(self);
                self.reg.setFlagsNZ(self.reg.a -% val);
                self.reg.setFlag("C", self.reg.a >= val);
            },
            .OpCpx => {
                const val = value.read(self);
                self.reg.setFlagsNZ(self.reg.x -% val);
                self.reg.setFlag("C", self.reg.x >= val);
            },
            .OpCpy => {
                const val = value.read(self);
                self.reg.setFlagsNZ(self.reg.y -% val);
                self.reg.setFlag("C", self.reg.y >= val);
            },
            .OpDec => {
                const val = value.read(self) -% 1;
                value.write(self, val);
                self.reg.setFlagsNZ(val);
            },
            .OpDex => {
                self.reg.x -%= 1;
                self.reg.setFlagsNZ(self.reg.x);
            },
            .OpDey => {
                self.reg.y -%= 1;
                self.reg.setFlagsNZ(self.reg.y);
            },
            .OpEor => {
                self.reg.a ^= value.read(self);
                self.reg.setFlagsNZ(self.reg.a);
            },
            .OpInc => {
                const val = value.read(self) +% 1;
                value.write(self, val);
                self.reg.setFlagsNZ(val);
            },
            .OpInx => {
                self.reg.x +%= 1;
                self.reg.setFlagsNZ(self.reg.x);
            },
            .OpIny => {
                self.reg.y +%= 1;
                self.reg.setFlagsNZ(self.reg.y);
            },
            .OpJmp => self.reg.pc = value.Memory -% 2,
            .OpJsr => {
                var push_sp = self.reg.pc +% 1;
                self.pushStack(@truncate(u8, push_sp >> 8));
                self.pushStack(@truncate(u8, push_sp));
                self.reg.pc = value.Memory -% 2;
            },
            .OpLda => {
                self.reg.a = value.read(self);
                self.reg.setFlagsNZ(self.reg.a);
            },
            .OpLdx => {
                self.reg.x = value.read(self);
                self.reg.setFlagsNZ(self.reg.x);
            },
            .OpLdy => {
                self.reg.y = value.read(self);
                self.reg.setFlagsNZ(self.reg.y);
            },
            .OpLsr => {
                const val = value.read(self);
                const new = val >> 1;

                value.write(self, new);
                self.reg.setFlagsNZ(new);
                self.reg.setFlags("C", val & 1);
            },
            .OpNop => {},
            .OpOra => {
                self.reg.a |= value.read(self);
                self.reg.setFlagsNZ(self.reg.a);
            },
            .OpPha => self.pushStack(self.reg.a),
            .OpPhp => self.pushStack(self.reg.p | 0b0011_0000),
            .OpPla => {
                self.reg.a = self.popStack();
                self.reg.setFlagsNZ(self.reg.a);
            },
            .OpPlp => self.reg.p = self.popStack(),
            .OpRol => {
                const val = value.read(self);
                const new = (val << 1) | self.reg.getFlags("C");

                value.write(self, new);
                self.reg.setFlagsNZ(new);
                self.reg.setFlags("C", (val & 0x80) >> 7);
            },
            .OpRor => {
                const val = value.read(self);
                const new = (val >> 1) | (self.reg.getFlags("C") << 7);

                value.write(self, new);
                self.reg.setFlagsNZ(new);
                self.reg.setFlags("C", val & 1);
            },
            .OpRti => {
                self.reg.p = self.popStack();
                const low = self.popStack();
                const high = @as(u16, self.popStack());
                self.reg.pc = (high << 8) | low;
            },
            .OpRts => {
                const low = self.popStack();
                const high = @as(u16, self.popStack());
                self.reg.pc = ((high << 8) | low) +% 1;
            },
            .OpSbc => {
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
            .OpSec => self.reg.setFlag("C", true),
            .OpSed => self.reg.setFlag("D", true),
            .OpSei => self.reg.setFlag("I", true),
            .OpSta => value.write(self, self.reg.a),
            .OpStx => value.write(self, self.reg.x),
            .OpSty => value.write(self, self.reg.y),
            .OpTax => {
                self.reg.x = self.reg.a;
                self.reg.setFlagsNZ(self.reg.x);
            },
            .OpTay => {
                self.reg.y = self.reg.a;
                self.reg.setFlagsNZ(self.reg.y);
            },
            .OpTsx => {
                self.reg.x = self.reg.s;
                self.reg.setFlagsNZ(self.reg.x);
            },
            .OpTxa => {
                self.reg.a = self.reg.x;
                self.reg.setFlagsNZ(self.reg.a);
            },
            .OpTxs => self.reg.s = self.reg.x,
            .OpTya => {
                self.reg.a = self.reg.y;
                self.reg.setFlagsNZ(self.reg.a);
            },
        }

        self.reg.pc +%= instruction.addressing.op_size() - 1;
        self.cycles += instruction.cycles;

        var i: usize = 0;
        while (i < @as(usize, instruction.cycles) * 3) : (i += 1) {
            self.ppu.runCycle();
        }
    }

    fn logInstruction(self: Cpu, instruction: Instruction(.Fast), value: ValueReference) void {
        const op_str = instruction.op.toString();

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
            .Accumulator => std.debug.print("A", .{}),
            .Absolute => {
                std.debug.print("${x:0>4}    \t; ${0x:0>4} = #${x:0>2}", .{ value.Memory, value.peek(self) });
            },
            .AbsoluteX => {
                std.debug.print("${x:0>4},x  \t; ${0x:0>4} = #${x:0>2}\tx = #${x:0>2}", .{
                    value.Memory,
                    value.peek(self),
                    self.reg.x,
                });
            },
            .AbsoluteY => {
                std.debug.print("${x:0>4},y  \t; ${0x:0>4} = #${x:0>2}\ty = #${x:0>2}", .{
                    value.Memory,
                    value.peek(self),
                    self.reg.y,
                });
            },
            .Immediate => std.debug.print("#${x:0>2}", .{low}),
            .Implied => {},
            .Indirect => {
                std.debug.print("(${x:0>4})  \t; (${0x:0>4}) = ${x:0>4}", .{ address, value.Memory });
            },
            .IndirectX => {
                std.debug.print("(${x:0>2},x)\t; (${0x:0>4},{x:0>2}) = ${x:0>4} = #${x:0>2}", .{
                    low,
                    self.reg.x,
                    value.Memory,
                    value.peek(self),
                });
            },
            .IndirectY => {
                std.debug.print("(${x:0>2}),y\t; (${0x:0>4}),{x:0>2} = ${x:0>4} = #${x:0>2}", .{
                    low,
                    self.reg.y,
                    value.Memory,
                    value.peek(self),
                });
            },
            .Relative => {
                const val = value.peek(self);
                const new_pc = @bitCast(u16, @bitCast(i16, self.reg.pc) +% @bitCast(i8, val) +% 1);
                std.debug.print("${x:0>2}      \t; PC ?= ${x:0>4}", .{ val, new_pc });
            },
            .ZeroPage => {
                std.debug.print("${x:0>2}      \t; ${0x:0>2} = #${x:0>2}", .{ value.Memory, value.peek(self) });
            },
            .ZeroPageX => {
                std.debug.print("${x:0>2},x    \t; ${0x:0>2} = #${x:0>2}", .{ value.Memory, value.peek(self) });
            },
            .ZeroPageY => {
                std.debug.print("${x:0>2},y    \t; ${0x:0>2} = #${x:0>2}", .{ value.Memory, value.peek(self) });
            },
        }

        std.debug.print("\n", .{});
    }
};
