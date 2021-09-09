const std = @import("std");
const Allocator = std.mem.Allocator;

const Instruction_ = @import("instruction.zig");
const Precision = Instruction_.Precision;
const Op = Instruction_.Op;
const Addressing = Instruction_.Addressing;
const Instruction = Instruction_.Instruction;

const Ines = @import("ines.zig");
const Cart_ = @import("cart.zig");
const Cart = Cart_.Cart;

pub const Cpu = struct {
    reg: Registers,
    mem: Memory,

    pub const Registers = struct {
        pc: u16,
        s: u8,

        a: u8,
        x: u8,
        y: u8,
        p: u8,

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

        pub fn hasFlags(comptime flags: []const u8) bool {
            for (flags) |c| {
                if (std.mem.indexOfScalar(u8, "NVDIZC", c) == null) {
                    return false;
                }
            }
            return true;
        }

        pub fn getFlagMask(comptime flags: []const u8) u8 {
            var mask: u8 = 0;
            for (flags) |c| {
                switch (c) {
                    'C' => mask |= 0b0000_0001,
                    'Z' => mask |= 0b0000_0010,
                    'I' => mask |= 0b0000_0100,
                    'D' => mask |= 0b0000_1000,
                    'V' => mask |= 0b0100_0000,
                    'N' => mask |= 0b1000_0000,
                    else => @compileError("Unknown flag name"),
                }
            }
            return mask;
        }

        pub fn getFlag(self: Registers, comptime flag: []const u8) bool {
            return (self.p & comptime Registers.getFlagMask(flag)) != 0;
        }

        pub fn setFlag(self: *Registers, comptime flag: []const u8, val: bool) void {
            self.setFlags(flag, if (val) @as(u8, 0xff) else 0);
        }

        pub fn getFlags(self: Registers, comptime flags: []const u8) u8 {
            return self.p & comptime Registers.getFlagMask(flags);
        }

        pub fn setFlags(self: *Registers, comptime flags: []const u8, val: u8) void {
            const mask = comptime Registers.getFlagMask(flags);
            self.p = (self.p & ~mask) | (val & mask);
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
        // incomplete
        cart: Cart,
        ram: [0x800]u8,
        ppu_regs: [0x8]u8,

        // TODO: implement non-zero pattern?
        pub fn zeroes() Memory {
            return Memory{
                .cart = Cart.init(),
                .ram = [_]u8{0} ** 0x800,
                .ppu_regs = [_]u8{0} ** 0x8,
            };
        }

        pub fn getPtr(self: *Memory, addr: u16) ?*u8 {
            switch (addr) {
                0x0000...0x1fff => return &self.ram[addr & 0x7ff],
                0x2000...0x3fff => return &self.ppu_regs[addr & 0x7],
                else => {
                    std.log.err("Unimplemented write memory address ({x:0>4})", .{addr});
                    return null;
                },
            }
        }

        pub const peek = read;

        pub fn read(self: Memory, addr: u16) u8 {
            switch (addr) {
                0x0000...0x1fff => return self.ram[addr & 0x7ff],
                0x2000...0x3fff => return self.ppu_regs[addr & 0x7],
                0x8000...0xffff => return self.cart.read(addr & 0x7fff),
                else => {
                    std.log.err("Unimplemented read memory address ({x:0>4})", .{addr});
                    return 0;
                },
            }
        }

        pub fn readWord(self: Memory, addr: u16) u16 {
            var low = self.read(addr);
            return (@as(u16, self.read(addr +% 1)) << 8) | low;
        }

        pub fn write(self: *Memory, addr: u16, val: u8) void {
            if (self.getPtr(addr)) |byte| {
                byte.* = val;
            }
        }
    };

    pub fn init() Cpu {
        return Cpu{
            .reg = Registers.startup(),
            .mem = Memory.zeroes(),
        };
    }

    pub fn deinit(self: Cpu, allocator: *Allocator) void {
        self.mem.cart.deinit(allocator);
    }

    pub fn loadRom(self: *Cpu, allocator: *Allocator, info: *Ines.RomInfo) void {
        std.log.debug("Loading rom", .{});
        self.mem.cart.loadRom(allocator, info);
        //self.reg.pc = self.mem.readWord(0xfffc);
        self.reg.pc = 0xc000;
        std.log.debug("PC set to {x:0>4}", .{self.reg.pc});
    }

    pub fn pushStack(self: *Cpu, val: u8) void {
        self.reg.s -%= 1;
        self.mem.write(@as(u9, self.reg.s) | 0x100, val);
    }

    pub fn popStack(self: *Cpu) u8 {
        const ret = self.mem.read(@as(u9, self.reg.s) | 0x100);
        self.reg.s +%= 1;
        return ret;
    }

    pub fn branchRelative(self: *Cpu, condition: bool, jump: u8) void {
        if (condition) {
            self.reg.pc = @bitCast(u16, @bitCast(i16, self.reg.pc) +% @bitCast(i8, jump));
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
        _ = precision;

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
                    break :blk ValueReference{ .Memory = self.mem.readWord(self.reg.pc) +% self.reg.x };
                },
                .AbsoluteY => {
                    break :blk ValueReference{ .Memory = self.mem.readWord(self.reg.pc) +% self.reg.y };
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

        self.logInstruction(instruction, value);

        switch (instruction.op) {
            .OpAdc => {
                const original: u8 = self.reg.a;
                const sum: u9 = @as(u9, self.reg.a) +
                    @as(u9, value.read(self)) +
                    @as(u9, self.reg.getFlags("C"));
                const sum_u8: u8 = @intCast(u8, sum & 0xff);
                self.reg.a = @intCast(u8, sum_u8);

                const n_flag = sum_u8 & 0x80;
                const v_flag = ((original & 0x80) ^ (sum_u8 & 0x80)) >> 6;
                const z_flag = @as(u8, @boolToInt(sum_u8 == 0)) << 1;
                const c_flag = @intCast(u8, (sum & 0x100) >> 8);
                self.reg.setFlags("NVZC", n_flag | v_flag | z_flag | c_flag);
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
                const val = self.reg.a & value.read(self);
                self.reg.setFlags("NV", val);
            },
            .OpBrk => {
                var push_sp = self.reg.pc +% 1;
                self.pushStack(@intCast(u8, push_sp >> 8));
                self.pushStack(@intCast(u8, push_sp & 0xff));
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
                self.pushStack(@intCast(u8, push_sp >> 8));
                self.pushStack(@intCast(u8, push_sp & 0xff));
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
                const original: u8 = self.reg.a;
                const dif: u9 = @as(u9, self.reg.a) -%
                    @as(u9, value.read(self)) -%
                    @as(u9, @boolToInt(!self.reg.getFlag("C")));
                const dif_u8: u8 = @intCast(u8, dif & 0xff);
                self.reg.a = @intCast(u8, dif_u8);

                const n_flag = dif_u8 & 0x80;
                const v_flag = ((original & 0x80) ^ (dif_u8 & 0x80)) >> 6;
                const z_flag = @as(u8, @boolToInt(dif_u8 == 0)) << 1;
                const c_flag = @intCast(u8, (dif & 0x100) >> 8);
                self.reg.setFlags("NVZC", n_flag | v_flag | z_flag | c_flag);
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
            .OpTxs => {
                self.reg.s = self.reg.x;
                self.reg.setFlagsNZ(self.reg.s);
            },
            .OpTya => {
                self.reg.a = self.reg.y;
                self.reg.setFlagsNZ(self.reg.a);
            },
        }

        self.reg.pc +%= instruction.addressing.op_size() - 1;
    }

    fn logInstruction(self: Cpu, instruction: Instruction(.Fast), value: ValueReference) void {
        const op_str = instruction.op.toString();

        const opcode = self.mem.peek(self.reg.pc -% 1);
        const low = self.mem.peek(self.reg.pc);
        const high = self.mem.peek(self.reg.pc +% 1);
        const address = (@as(u16, high) << 8) | low;

        std.debug.print("A: {x:0>2} X: {x:0>2} Y: {x:0>2} P: {x:0>2} S: {x:0>2} PC: {x:0>4}\t", .{
            self.reg.a,
            self.reg.x,
            self.reg.y,
            self.reg.p,
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
                std.debug.print("(${x:0>4},x)\t; (${0x:0>4},{x:0>2}) = ${x:0>4} = #${x:0>2}", .{
                    address,
                    self.reg.x,
                    value.Memory,
                    value.peek(self),
                });
            },
            .IndirectY => {
                std.debug.print("(${x:0>4}),y\t; (${0x:0>4}),{x:0>2} = ${x:0>4} = #${x:0>2}", .{
                    address,
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
