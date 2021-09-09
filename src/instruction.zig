const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;

// TODO: LUT this mess

pub const Precision = enum {
    Fast,
    Accurate,
};

pub fn Op(comptime precision: Precision) type {
    _ = precision;
    return enum {
        OpAdc,
        OpAnd,
        OpAsl,
        OpBpl,
        OpBmi,
        OpBvc,
        OpBvs,
        OpBcc,
        OpBcs,
        OpBne,
        OpBeq,
        OpBit,
        OpBrk,
        OpClc,
        OpCld,
        OpCli,
        OpClv,
        OpCmp,
        OpCpx,
        OpCpy,
        OpDec,
        OpDex,
        OpDey,
        OpEor,
        OpInc,
        OpInx,
        OpIny,
        OpJmp,
        OpJsr,
        OpLda,
        OpLdx,
        OpLdy,
        OpLsr,
        OpNop,
        OpOra,
        OpPha,
        OpPhp,
        OpPla,
        OpPlp,
        OpRol,
        OpRor,
        OpRti,
        OpRts,
        OpSbc,
        OpSec,
        OpSed,
        OpSei,
        OpSta,
        OpStx,
        OpSty,
        OpTax,
        OpTay,
        OpTsx,
        OpTxa,
        OpTxs,
        OpTya,

        pub fn toString(self: @This()) []const u8 {
            const enum_strs = comptime blk: {
                const enum_fields = @typeInfo(@This()).Enum.fields;
                var arr = [_]([3]u8){undefined} ** enum_fields.len;
                for (arr) |*idx, i| {
                    _ = std.ascii.upperString(idx[0..], enum_fields[i].name[2..]);
                }
                break :blk arr;
            };
            return enum_strs[@enumToInt(self)][0..];
        }
    };
}

pub const Addressing = enum {
    Accumulator,
    Absolute,
    AbsoluteX,
    AbsoluteY,
    Immediate,
    Implied,
    Indirect,
    IndirectX,
    IndirectY,
    Relative,
    ZeroPage,
    ZeroPageX,
    ZeroPageY,

    pub fn op_size(self: Addressing) u2 {
        return switch (self) {
            .Accumulator => 1,
            .Absolute => 3,
            .AbsoluteX => 3,
            .AbsoluteY => 3,
            .Immediate => 2,
            .Implied => 1,
            .Indirect => 3,
            .IndirectX => 2,
            .IndirectY => 2,
            .Relative => 2,
            .ZeroPage => 2,
            .ZeroPageX => 2,
            .ZeroPageY => 2,
        };
    }

    pub fn toString(self: Addressing) ?[]const u8 {
        return switch (self) {
            .Accumulator => "A",
            .Absolute => "$word",
            .AbsoluteX => "$word,X",
            .AbsoluteY => "$word,Y",
            .Immediate => "#$byte",
            .Implied => null,
            .Indirect => "($word)",
            .IndirectX => "($byte,X)",
            .IndirectY => "($byte),Y",
            .Relative => "$byte",
            .ZeroPage => "$byte",
            .ZeroPageX => "$byte,X",
            .ZeroPageY => "$byte,Y",
        };
    }
};

pub fn Instruction(comptime precision: Precision) type {
    return struct {
        op: Op(precision),
        addressing: Addressing,

        pub fn decode(opcode: u8) @This() {
            return switch (precision) {
                .Fast => decodeFast(opcode),
                .Accurate => decodeAccurate(opcode),
            };
        }

        pub fn format(self: @This(), comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
            _ = options;
            const addressing_str = self.addressing.toString();
            if (fmt.len == 0) { // or comptime std.mem.eql(u8, fmt, "p")) {
                if (addressing_str) |str| {
                    return std.fmt.format(writer, "{s} {s}", .{ self.op.toString(), str });
                } else {
                    return std.fmt.format(writer, "{s}", .{self.op.toString()});
                }
            } else {
                @compileError("Unknown format character: '" ++ fmt ++ "'");
            }
        }
    };
}

fn decodeFast(opcode: u8) Instruction(.Fast) {
    const OpFast = Op(.Fast);

    switch (opcode) {
        0x69 => return .{ .op = OpFast.OpAdc, .addressing = Addressing.Immediate },
        0x65 => return .{ .op = OpFast.OpAdc, .addressing = Addressing.ZeroPage },
        0x75 => return .{ .op = OpFast.OpAdc, .addressing = Addressing.ZeroPageX },
        0x6d => return .{ .op = OpFast.OpAdc, .addressing = Addressing.Absolute },
        0x7d => return .{ .op = OpFast.OpAdc, .addressing = Addressing.AbsoluteX },
        0x79 => return .{ .op = OpFast.OpAdc, .addressing = Addressing.AbsoluteY },
        0x61 => return .{ .op = OpFast.OpAdc, .addressing = Addressing.IndirectX },
        0x71 => return .{ .op = OpFast.OpAdc, .addressing = Addressing.IndirectY },

        0x29 => return .{ .op = OpFast.OpAnd, .addressing = Addressing.Immediate },
        0x25 => return .{ .op = OpFast.OpAnd, .addressing = Addressing.ZeroPage },
        0x35 => return .{ .op = OpFast.OpAnd, .addressing = Addressing.ZeroPageX },
        0x2d => return .{ .op = OpFast.OpAnd, .addressing = Addressing.Absolute },
        0x3d => return .{ .op = OpFast.OpAnd, .addressing = Addressing.AbsoluteX },
        0x39 => return .{ .op = OpFast.OpAnd, .addressing = Addressing.AbsoluteY },
        0x21 => return .{ .op = OpFast.OpAnd, .addressing = Addressing.IndirectX },
        0x31 => return .{ .op = OpFast.OpAnd, .addressing = Addressing.IndirectY },

        0x0a => return .{ .op = OpFast.OpAsl, .addressing = Addressing.Accumulator },
        0x06 => return .{ .op = OpFast.OpAsl, .addressing = Addressing.ZeroPage },
        0x16 => return .{ .op = OpFast.OpAsl, .addressing = Addressing.ZeroPageX },
        0x0e => return .{ .op = OpFast.OpAsl, .addressing = Addressing.Absolute },
        0x1e => return .{ .op = OpFast.OpAsl, .addressing = Addressing.AbsoluteX },

        0x10 => return .{ .op = OpFast.OpBpl, .addressing = Addressing.Relative },
        0x30 => return .{ .op = OpFast.OpBmi, .addressing = Addressing.Relative },
        0x50 => return .{ .op = OpFast.OpBvc, .addressing = Addressing.Relative },
        0x70 => return .{ .op = OpFast.OpBvs, .addressing = Addressing.Relative },
        0x90 => return .{ .op = OpFast.OpBcc, .addressing = Addressing.Relative },
        0xb0 => return .{ .op = OpFast.OpBcs, .addressing = Addressing.Relative },
        0xd0 => return .{ .op = OpFast.OpBne, .addressing = Addressing.Relative },
        0xf0 => return .{ .op = OpFast.OpBeq, .addressing = Addressing.Relative },

        0x24 => return .{ .op = OpFast.OpBit, .addressing = Addressing.ZeroPage },
        0x2c => return .{ .op = OpFast.OpBit, .addressing = Addressing.Absolute },

        0x00 => return .{ .op = OpFast.OpBrk, .addressing = Addressing.Implied },

        0x18 => return .{ .op = OpFast.OpClc, .addressing = Addressing.Implied },
        0xd8 => return .{ .op = OpFast.OpCld, .addressing = Addressing.Implied },
        0x58 => return .{ .op = OpFast.OpCli, .addressing = Addressing.Implied },
        0xb8 => return .{ .op = OpFast.OpClv, .addressing = Addressing.Implied },

        0xc9 => return .{ .op = OpFast.OpCmp, .addressing = Addressing.Immediate },
        0xc5 => return .{ .op = OpFast.OpCmp, .addressing = Addressing.ZeroPage },
        0xd5 => return .{ .op = OpFast.OpCmp, .addressing = Addressing.ZeroPageX },
        0xcd => return .{ .op = OpFast.OpCmp, .addressing = Addressing.Absolute },
        0xdd => return .{ .op = OpFast.OpCmp, .addressing = Addressing.AbsoluteX },
        0xd9 => return .{ .op = OpFast.OpCmp, .addressing = Addressing.AbsoluteY },
        0xc1 => return .{ .op = OpFast.OpCmp, .addressing = Addressing.IndirectX },
        0xd1 => return .{ .op = OpFast.OpCmp, .addressing = Addressing.IndirectY },

        0xe0 => return .{ .op = OpFast.OpCpx, .addressing = Addressing.Immediate },
        0xe4 => return .{ .op = OpFast.OpCpx, .addressing = Addressing.ZeroPage },
        0xec => return .{ .op = OpFast.OpCpx, .addressing = Addressing.Absolute },

        0xc0 => return .{ .op = OpFast.OpCpy, .addressing = Addressing.Immediate },
        0xc4 => return .{ .op = OpFast.OpCpy, .addressing = Addressing.ZeroPage },
        0xcc => return .{ .op = OpFast.OpCpy, .addressing = Addressing.Absolute },

        0xc6 => return .{ .op = OpFast.OpDec, .addressing = Addressing.ZeroPage },
        0xd6 => return .{ .op = OpFast.OpDec, .addressing = Addressing.ZeroPageX },
        0xce => return .{ .op = OpFast.OpDec, .addressing = Addressing.Absolute },
        0xde => return .{ .op = OpFast.OpDec, .addressing = Addressing.AbsoluteX },

        0xca => return .{ .op = OpFast.OpDex, .addressing = Addressing.Implied },
        0x88 => return .{ .op = OpFast.OpDey, .addressing = Addressing.Implied },

        0x49 => return .{ .op = OpFast.OpEor, .addressing = Addressing.Immediate },
        0x45 => return .{ .op = OpFast.OpEor, .addressing = Addressing.ZeroPage },
        0x55 => return .{ .op = OpFast.OpEor, .addressing = Addressing.ZeroPageX },
        0x4d => return .{ .op = OpFast.OpEor, .addressing = Addressing.Absolute },
        0x5d => return .{ .op = OpFast.OpEor, .addressing = Addressing.AbsoluteX },
        0x59 => return .{ .op = OpFast.OpEor, .addressing = Addressing.AbsoluteY },
        0x41 => return .{ .op = OpFast.OpEor, .addressing = Addressing.IndirectX },
        0x51 => return .{ .op = OpFast.OpEor, .addressing = Addressing.IndirectY },

        0xe6 => return .{ .op = OpFast.OpInc, .addressing = Addressing.ZeroPage },
        0xf6 => return .{ .op = OpFast.OpInc, .addressing = Addressing.ZeroPageX },
        0xee => return .{ .op = OpFast.OpInc, .addressing = Addressing.Absolute },
        0xfe => return .{ .op = OpFast.OpInc, .addressing = Addressing.AbsoluteX },

        0xe8 => return .{ .op = OpFast.OpInx, .addressing = Addressing.Implied },
        0xc8 => return .{ .op = OpFast.OpIny, .addressing = Addressing.Implied },

        0x4c => return .{ .op = OpFast.OpJmp, .addressing = Addressing.Absolute },
        0x6c => return .{ .op = OpFast.OpJmp, .addressing = Addressing.Indirect },

        0x20 => return .{ .op = OpFast.OpJsr, .addressing = Addressing.Absolute },

        0xa9 => return .{ .op = OpFast.OpLda, .addressing = Addressing.Immediate },
        0xa5 => return .{ .op = OpFast.OpLda, .addressing = Addressing.ZeroPage },
        0xb5 => return .{ .op = OpFast.OpLda, .addressing = Addressing.ZeroPageX },
        0xad => return .{ .op = OpFast.OpLda, .addressing = Addressing.Absolute },
        0xbd => return .{ .op = OpFast.OpLda, .addressing = Addressing.AbsoluteX },
        0xb9 => return .{ .op = OpFast.OpLda, .addressing = Addressing.AbsoluteY },
        0xa1 => return .{ .op = OpFast.OpLda, .addressing = Addressing.IndirectX },
        0xb1 => return .{ .op = OpFast.OpLda, .addressing = Addressing.IndirectY },

        0xa2 => return .{ .op = OpFast.OpLdx, .addressing = Addressing.Immediate },
        0xa6 => return .{ .op = OpFast.OpLdx, .addressing = Addressing.ZeroPage },
        0xb6 => return .{ .op = OpFast.OpLdx, .addressing = Addressing.ZeroPageY },
        0xae => return .{ .op = OpFast.OpLdx, .addressing = Addressing.Absolute },
        0xbe => return .{ .op = OpFast.OpLdx, .addressing = Addressing.AbsoluteY },

        0xa0 => return .{ .op = OpFast.OpLdy, .addressing = Addressing.Immediate },
        0xa4 => return .{ .op = OpFast.OpLdy, .addressing = Addressing.ZeroPage },
        0xb4 => return .{ .op = OpFast.OpLdy, .addressing = Addressing.ZeroPageX },
        0xac => return .{ .op = OpFast.OpLdy, .addressing = Addressing.Absolute },
        0xbc => return .{ .op = OpFast.OpLdy, .addressing = Addressing.AbsoluteX },

        0x4a => return .{ .op = OpFast.OpLsr, .addressing = Addressing.Accumulator },
        0x46 => return .{ .op = OpFast.OpLsr, .addressing = Addressing.ZeroPage },
        0x56 => return .{ .op = OpFast.OpLsr, .addressing = Addressing.ZeroPageX },
        0x4e => return .{ .op = OpFast.OpLsr, .addressing = Addressing.Absolute },
        0x5e => return .{ .op = OpFast.OpLsr, .addressing = Addressing.AbsoluteX },

        0xea => return .{ .op = OpFast.OpNop, .addressing = Addressing.Implied },

        0x09 => return .{ .op = OpFast.OpOra, .addressing = Addressing.Immediate },
        0x05 => return .{ .op = OpFast.OpOra, .addressing = Addressing.ZeroPage },
        0x15 => return .{ .op = OpFast.OpOra, .addressing = Addressing.ZeroPageX },
        0x0d => return .{ .op = OpFast.OpOra, .addressing = Addressing.Absolute },
        0x1d => return .{ .op = OpFast.OpOra, .addressing = Addressing.AbsoluteX },
        0x19 => return .{ .op = OpFast.OpOra, .addressing = Addressing.AbsoluteY },
        0x01 => return .{ .op = OpFast.OpOra, .addressing = Addressing.IndirectX },
        0x11 => return .{ .op = OpFast.OpOra, .addressing = Addressing.IndirectY },

        0x48 => return .{ .op = OpFast.OpPha, .addressing = Addressing.Implied },
        0x08 => return .{ .op = OpFast.OpPhp, .addressing = Addressing.Implied },
        0x68 => return .{ .op = OpFast.OpPla, .addressing = Addressing.Implied },
        0x28 => return .{ .op = OpFast.OpPlp, .addressing = Addressing.Implied },

        0x2a => return .{ .op = OpFast.OpRol, .addressing = Addressing.Accumulator },
        0x26 => return .{ .op = OpFast.OpRol, .addressing = Addressing.ZeroPage },
        0x36 => return .{ .op = OpFast.OpRol, .addressing = Addressing.ZeroPageX },
        0x2e => return .{ .op = OpFast.OpRol, .addressing = Addressing.Absolute },
        0x3e => return .{ .op = OpFast.OpRol, .addressing = Addressing.AbsoluteX },

        0x6a => return .{ .op = OpFast.OpRor, .addressing = Addressing.Accumulator },
        0x66 => return .{ .op = OpFast.OpRor, .addressing = Addressing.ZeroPage },
        0x76 => return .{ .op = OpFast.OpRor, .addressing = Addressing.ZeroPageX },
        0x6e => return .{ .op = OpFast.OpRor, .addressing = Addressing.Absolute },
        0x7e => return .{ .op = OpFast.OpRor, .addressing = Addressing.AbsoluteX },

        0x40 => return .{ .op = OpFast.OpRti, .addressing = Addressing.Implied },
        0x60 => return .{ .op = OpFast.OpRts, .addressing = Addressing.Implied },

        0xe9 => return .{ .op = OpFast.OpSbc, .addressing = Addressing.Immediate },
        0xe5 => return .{ .op = OpFast.OpSbc, .addressing = Addressing.ZeroPage },
        0xf5 => return .{ .op = OpFast.OpSbc, .addressing = Addressing.ZeroPageX },
        0xed => return .{ .op = OpFast.OpSbc, .addressing = Addressing.Absolute },
        0xfd => return .{ .op = OpFast.OpSbc, .addressing = Addressing.AbsoluteX },
        0xf9 => return .{ .op = OpFast.OpSbc, .addressing = Addressing.AbsoluteY },
        0xe1 => return .{ .op = OpFast.OpSbc, .addressing = Addressing.IndirectX },
        0xf1 => return .{ .op = OpFast.OpSbc, .addressing = Addressing.IndirectY },

        0x38 => return .{ .op = OpFast.OpSec, .addressing = Addressing.Implied },
        0xf8 => return .{ .op = OpFast.OpSed, .addressing = Addressing.Implied },
        0x78 => return .{ .op = OpFast.OpSei, .addressing = Addressing.Implied },

        0x85 => return .{ .op = OpFast.OpSta, .addressing = Addressing.ZeroPage },
        0x95 => return .{ .op = OpFast.OpSta, .addressing = Addressing.ZeroPageX },
        0x8d => return .{ .op = OpFast.OpSta, .addressing = Addressing.Absolute },
        0x9d => return .{ .op = OpFast.OpSta, .addressing = Addressing.AbsoluteX },
        0x99 => return .{ .op = OpFast.OpSta, .addressing = Addressing.AbsoluteY },
        0x81 => return .{ .op = OpFast.OpSta, .addressing = Addressing.IndirectX },
        0x91 => return .{ .op = OpFast.OpSta, .addressing = Addressing.IndirectY },

        0x86 => return .{ .op = OpFast.OpStx, .addressing = Addressing.ZeroPage },
        0x96 => return .{ .op = OpFast.OpStx, .addressing = Addressing.ZeroPageY },
        0x8e => return .{ .op = OpFast.OpStx, .addressing = Addressing.Absolute },

        0x84 => return .{ .op = OpFast.OpSty, .addressing = Addressing.ZeroPage },
        0x94 => return .{ .op = OpFast.OpSty, .addressing = Addressing.ZeroPageX },
        0x8c => return .{ .op = OpFast.OpSty, .addressing = Addressing.Absolute },

        0xaa => return .{ .op = OpFast.OpTax, .addressing = Addressing.Implied },
        0xa8 => return .{ .op = OpFast.OpTay, .addressing = Addressing.Implied },
        0xba => return .{ .op = OpFast.OpTsx, .addressing = Addressing.Implied },
        0x8a => return .{ .op = OpFast.OpTxa, .addressing = Addressing.Implied },
        0x9a => return .{ .op = OpFast.OpTxs, .addressing = Addressing.Implied },
        0x98 => return .{ .op = OpFast.OpTya, .addressing = Addressing.Implied },

        else => @panic("Not implemented"),
    }
}

// TODO: finish later
// https://llx.com/Neil/a2/opcodes.html#insc02
fn decodeAccurate(opcode: u8) Instruction(.Accurate) {
    const OpAcc = Op(.Accurate);

    const aaa: u3 = @intCast(u3, (opcode >> 5) & 0b111);
    const bbb: u3 = @intCast(u3, (opcode >> 2) & 0b111);
    const cc: u2 = @intCast(u2, opcode & 0b11);

    switch (cc) {
        0b00 => {
            const op = switch (aaa) {
                0b001 => OpAcc.OpBit,
                0b010 => OpAcc.OpJmp,
                0b100 => OpAcc.OpSty,
                0b101 => OpAcc.OpLdy,
                0b110 => OpAcc.OpCpy,
                0b111 => OpAcc.OpCpx,
                else => @panic("Not yet implemented: 0b00 - op"),
            };
            const addressing = switch (bbb) {
                0b000 => Addressing.Immediate,
                0b001 => Addressing.ZeroPage,
                0b011 => Addressing.Absolute,
                0b101 => Addressing.ZeroPageX,
                0b111 => Addressing.AbsoluteX,
                else => @panic("Not yet implemented: 0b00 - addressing"),
            };
            return .{
                .op = op,
                .addressing = addressing,
            };
        },
        0b01 => {
            const op = switch (aaa) {
                0b000 => OpAcc.OpOra,
                0b001 => OpAcc.OpAnd,
                0b010 => OpAcc.OpEor,
                0b011 => OpAcc.OpAdc,
                0b100 => OpAcc.OpSta,
                0b101 => OpAcc.OpLda,
                0b110 => OpAcc.OpCmp,
                0b111 => OpAcc.OpSbc,
            };
            const addressing = switch (bbb) {
                0b000 => Addressing.IndirectX,
                0b001 => Addressing.ZeroPage,
                0b010 => Addressing.Immediate,
                0b011 => Addressing.Absolute,
                0b100 => Addressing.IndirectY,
                0b101 => Addressing.ZeroPageX,
                0b110 => Addressing.AbsoluteY,
                0b111 => Addressing.AbsoluteX,
            };
            return .{
                .op = op,
                .addressing = addressing,
            };
        },
        0b10 => {
            const op = switch (aaa) {
                0b000 => OpAcc.OpAsl,
                0b001 => OpAcc.OpRol,
                0b010 => OpAcc.OpLsr,
                0b011 => OpAcc.OpRor,
                0b100 => OpAcc.OpStx,
                0b101 => OpAcc.OpLdx,
                0b110 => OpAcc.OpDec,
                0b111 => OpAcc.OpInc,
            };
            const addressing = switch (bbb) {
                0b000 => Addressing.Immediate,
                0b001 => Addressing.ZeroPage,
                0b010 => Addressing.Accumulator,
                0b011 => Addressing.Absolute,
                0b101 => if (op == OpAcc.OpStx or op == OpAcc.OpLdx) Addressing.ZeroPageY else Addressing.ZeroPageX,
                0b111 => if (op == OpAcc.OpLdx) Addressing.ZeroPageY else Addressing.AbsoluteX,
                else => @panic("Not yet implemented: 0b10 - addressing"),
            };
            return .{
                .op = op,
                .addressing = addressing,
            };
        },
        else => @panic("Not yet implemented"),
    }
}
