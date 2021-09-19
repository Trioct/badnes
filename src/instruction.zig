const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Precision = @import("console.zig").Precision;

// TODO: LUT this mess

pub fn Op(comptime precision: Precision) type {
    _ = precision;
    return enum {
        OpIll,

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
};

pub fn Instruction(comptime precision: Precision) type {
    switch (precision) {
        .Fast => return struct {
            op: Op(.Fast),
            addressing: Addressing,
            cycles: u3,
            var_cycles: bool = false,

            pub const decode = decodeFast;
        },
        .Accurate => return struct {
            op: Op(.Accurate),
            addressing: Addressing,

            pub const decode = decodeAccurate;
        },
    }
}

fn decodeFast(opcode: u8) Instruction(.Fast) {
    const OpFast = Op(.Fast);

    return switch (opcode) {
        0x69 => .{ .op = OpFast.OpAdc, .addressing = Addressing.Immediate, .cycles = 2 },
        0x65 => .{ .op = OpFast.OpAdc, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0x75 => .{ .op = OpFast.OpAdc, .addressing = Addressing.ZeroPageX, .cycles = 4 },
        0x6d => .{ .op = OpFast.OpAdc, .addressing = Addressing.Absolute, .cycles = 4 },
        0x7d => .{ .op = OpFast.OpAdc, .addressing = Addressing.AbsoluteX, .cycles = 4, .var_cycles = true },
        0x79 => .{ .op = OpFast.OpAdc, .addressing = Addressing.AbsoluteY, .cycles = 4, .var_cycles = true },
        0x61 => .{ .op = OpFast.OpAdc, .addressing = Addressing.IndirectX, .cycles = 6 },
        0x71 => .{ .op = OpFast.OpAdc, .addressing = Addressing.IndirectY, .cycles = 5, .var_cycles = true },

        0x29 => .{ .op = OpFast.OpAnd, .addressing = Addressing.Immediate, .cycles = 2 },
        0x25 => .{ .op = OpFast.OpAnd, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0x35 => .{ .op = OpFast.OpAnd, .addressing = Addressing.ZeroPageX, .cycles = 4 },
        0x2d => .{ .op = OpFast.OpAnd, .addressing = Addressing.Absolute, .cycles = 4 },
        0x3d => .{ .op = OpFast.OpAnd, .addressing = Addressing.AbsoluteX, .cycles = 4, .var_cycles = true },
        0x39 => .{ .op = OpFast.OpAnd, .addressing = Addressing.AbsoluteY, .cycles = 4, .var_cycles = true },
        0x21 => .{ .op = OpFast.OpAnd, .addressing = Addressing.IndirectX, .cycles = 6 },
        0x31 => .{ .op = OpFast.OpAnd, .addressing = Addressing.IndirectY, .cycles = 5, .var_cycles = true },

        0x0a => .{ .op = OpFast.OpAsl, .addressing = Addressing.Accumulator, .cycles = 2 },
        0x06 => .{ .op = OpFast.OpAsl, .addressing = Addressing.ZeroPage, .cycles = 5 },
        0x16 => .{ .op = OpFast.OpAsl, .addressing = Addressing.ZeroPageX, .cycles = 6 },
        0x0e => .{ .op = OpFast.OpAsl, .addressing = Addressing.Absolute, .cycles = 6 },
        0x1e => .{ .op = OpFast.OpAsl, .addressing = Addressing.AbsoluteX, .cycles = 7 },

        0x10 => .{ .op = OpFast.OpBpl, .addressing = Addressing.Relative, .cycles = 2 },
        0x30 => .{ .op = OpFast.OpBmi, .addressing = Addressing.Relative, .cycles = 2 },
        0x50 => .{ .op = OpFast.OpBvc, .addressing = Addressing.Relative, .cycles = 2 },
        0x70 => .{ .op = OpFast.OpBvs, .addressing = Addressing.Relative, .cycles = 2 },
        0x90 => .{ .op = OpFast.OpBcc, .addressing = Addressing.Relative, .cycles = 2 },
        0xb0 => .{ .op = OpFast.OpBcs, .addressing = Addressing.Relative, .cycles = 2 },
        0xd0 => .{ .op = OpFast.OpBne, .addressing = Addressing.Relative, .cycles = 2 },
        0xf0 => .{ .op = OpFast.OpBeq, .addressing = Addressing.Relative, .cycles = 2 },

        0x24 => .{ .op = OpFast.OpBit, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0x2c => .{ .op = OpFast.OpBit, .addressing = Addressing.Absolute, .cycles = 4 },

        0x00 => .{ .op = OpFast.OpBrk, .addressing = Addressing.Implied, .cycles = 7 },

        0x18 => .{ .op = OpFast.OpClc, .addressing = Addressing.Implied, .cycles = 2 },
        0xd8 => .{ .op = OpFast.OpCld, .addressing = Addressing.Implied, .cycles = 2 },
        0x58 => .{ .op = OpFast.OpCli, .addressing = Addressing.Implied, .cycles = 2 },
        0xb8 => .{ .op = OpFast.OpClv, .addressing = Addressing.Implied, .cycles = 2 },

        0xc9 => .{ .op = OpFast.OpCmp, .addressing = Addressing.Immediate, .cycles = 2 },
        0xc5 => .{ .op = OpFast.OpCmp, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0xd5 => .{ .op = OpFast.OpCmp, .addressing = Addressing.ZeroPageX, .cycles = 4 },
        0xcd => .{ .op = OpFast.OpCmp, .addressing = Addressing.Absolute, .cycles = 4 },
        0xdd => .{ .op = OpFast.OpCmp, .addressing = Addressing.AbsoluteX, .cycles = 4, .var_cycles = true },
        0xd9 => .{ .op = OpFast.OpCmp, .addressing = Addressing.AbsoluteY, .cycles = 4, .var_cycles = true },
        0xc1 => .{ .op = OpFast.OpCmp, .addressing = Addressing.IndirectX, .cycles = 6 },
        0xd1 => .{ .op = OpFast.OpCmp, .addressing = Addressing.IndirectY, .cycles = 5, .var_cycles = true },

        0xe0 => .{ .op = OpFast.OpCpx, .addressing = Addressing.Immediate, .cycles = 2 },
        0xe4 => .{ .op = OpFast.OpCpx, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0xec => .{ .op = OpFast.OpCpx, .addressing = Addressing.Absolute, .cycles = 4 },

        0xc0 => .{ .op = OpFast.OpCpy, .addressing = Addressing.Immediate, .cycles = 2 },
        0xc4 => .{ .op = OpFast.OpCpy, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0xcc => .{ .op = OpFast.OpCpy, .addressing = Addressing.Absolute, .cycles = 4 },

        0xc6 => .{ .op = OpFast.OpDec, .addressing = Addressing.ZeroPage, .cycles = 5 },
        0xd6 => .{ .op = OpFast.OpDec, .addressing = Addressing.ZeroPageX, .cycles = 6 },
        0xce => .{ .op = OpFast.OpDec, .addressing = Addressing.Absolute, .cycles = 6 },
        0xde => .{ .op = OpFast.OpDec, .addressing = Addressing.AbsoluteX, .cycles = 7 },

        0xca => .{ .op = OpFast.OpDex, .addressing = Addressing.Implied, .cycles = 2 },
        0x88 => .{ .op = OpFast.OpDey, .addressing = Addressing.Implied, .cycles = 2 },

        0x49 => .{ .op = OpFast.OpEor, .addressing = Addressing.Immediate, .cycles = 2 },
        0x45 => .{ .op = OpFast.OpEor, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0x55 => .{ .op = OpFast.OpEor, .addressing = Addressing.ZeroPageX, .cycles = 4 },
        0x4d => .{ .op = OpFast.OpEor, .addressing = Addressing.Absolute, .cycles = 4 },
        0x5d => .{ .op = OpFast.OpEor, .addressing = Addressing.AbsoluteX, .cycles = 4, .var_cycles = true },
        0x59 => .{ .op = OpFast.OpEor, .addressing = Addressing.AbsoluteY, .cycles = 4, .var_cycles = true },
        0x41 => .{ .op = OpFast.OpEor, .addressing = Addressing.IndirectX, .cycles = 6 },
        0x51 => .{ .op = OpFast.OpEor, .addressing = Addressing.IndirectY, .cycles = 5, .var_cycles = true },

        0xe6 => .{ .op = OpFast.OpInc, .addressing = Addressing.ZeroPage, .cycles = 5 },
        0xf6 => .{ .op = OpFast.OpInc, .addressing = Addressing.ZeroPageX, .cycles = 6 },
        0xee => .{ .op = OpFast.OpInc, .addressing = Addressing.Absolute, .cycles = 6 },
        0xfe => .{ .op = OpFast.OpInc, .addressing = Addressing.AbsoluteX, .cycles = 7 },

        0xe8 => .{ .op = OpFast.OpInx, .addressing = Addressing.Implied, .cycles = 2 },
        0xc8 => .{ .op = OpFast.OpIny, .addressing = Addressing.Implied, .cycles = 2 },

        0x4c => .{ .op = OpFast.OpJmp, .addressing = Addressing.Absolute, .cycles = 3 },
        0x6c => .{ .op = OpFast.OpJmp, .addressing = Addressing.Indirect, .cycles = 5 },

        0x20 => .{ .op = OpFast.OpJsr, .addressing = Addressing.Absolute, .cycles = 6 },

        0xa9 => .{ .op = OpFast.OpLda, .addressing = Addressing.Immediate, .cycles = 2 },
        0xa5 => .{ .op = OpFast.OpLda, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0xb5 => .{ .op = OpFast.OpLda, .addressing = Addressing.ZeroPageX, .cycles = 4 },
        0xad => .{ .op = OpFast.OpLda, .addressing = Addressing.Absolute, .cycles = 4 },
        0xbd => .{ .op = OpFast.OpLda, .addressing = Addressing.AbsoluteX, .cycles = 4, .var_cycles = true },
        0xb9 => .{ .op = OpFast.OpLda, .addressing = Addressing.AbsoluteY, .cycles = 4, .var_cycles = true },
        0xa1 => .{ .op = OpFast.OpLda, .addressing = Addressing.IndirectX, .cycles = 6 },
        0xb1 => .{ .op = OpFast.OpLda, .addressing = Addressing.IndirectY, .cycles = 5, .var_cycles = true },

        0xa2 => .{ .op = OpFast.OpLdx, .addressing = Addressing.Immediate, .cycles = 2 },
        0xa6 => .{ .op = OpFast.OpLdx, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0xb6 => .{ .op = OpFast.OpLdx, .addressing = Addressing.ZeroPageY, .cycles = 4 },
        0xae => .{ .op = OpFast.OpLdx, .addressing = Addressing.Absolute, .cycles = 4 },
        0xbe => .{ .op = OpFast.OpLdx, .addressing = Addressing.AbsoluteY, .cycles = 4, .var_cycles = true },

        0xa0 => .{ .op = OpFast.OpLdy, .addressing = Addressing.Immediate, .cycles = 2 },
        0xa4 => .{ .op = OpFast.OpLdy, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0xb4 => .{ .op = OpFast.OpLdy, .addressing = Addressing.ZeroPageX, .cycles = 4 },
        0xac => .{ .op = OpFast.OpLdy, .addressing = Addressing.Absolute, .cycles = 4 },
        0xbc => .{ .op = OpFast.OpLdy, .addressing = Addressing.AbsoluteX, .cycles = 4, .var_cycles = true },

        0x4a => .{ .op = OpFast.OpLsr, .addressing = Addressing.Accumulator, .cycles = 2 },
        0x46 => .{ .op = OpFast.OpLsr, .addressing = Addressing.ZeroPage, .cycles = 5 },
        0x56 => .{ .op = OpFast.OpLsr, .addressing = Addressing.ZeroPageX, .cycles = 6 },
        0x4e => .{ .op = OpFast.OpLsr, .addressing = Addressing.Absolute, .cycles = 6 },
        0x5e => .{ .op = OpFast.OpLsr, .addressing = Addressing.AbsoluteX, .cycles = 7 },

        0xea => .{ .op = OpFast.OpNop, .addressing = Addressing.Implied, .cycles = 2 },

        0x09 => .{ .op = OpFast.OpOra, .addressing = Addressing.Immediate, .cycles = 2 },
        0x05 => .{ .op = OpFast.OpOra, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0x15 => .{ .op = OpFast.OpOra, .addressing = Addressing.ZeroPageX, .cycles = 4 },
        0x0d => .{ .op = OpFast.OpOra, .addressing = Addressing.Absolute, .cycles = 4 },
        0x1d => .{ .op = OpFast.OpOra, .addressing = Addressing.AbsoluteX, .cycles = 4, .var_cycles = true },
        0x19 => .{ .op = OpFast.OpOra, .addressing = Addressing.AbsoluteY, .cycles = 4, .var_cycles = true },
        0x01 => .{ .op = OpFast.OpOra, .addressing = Addressing.IndirectX, .cycles = 6 },
        0x11 => .{ .op = OpFast.OpOra, .addressing = Addressing.IndirectY, .cycles = 5, .var_cycles = true },

        0x48 => .{ .op = OpFast.OpPha, .addressing = Addressing.Implied, .cycles = 3 },
        0x08 => .{ .op = OpFast.OpPhp, .addressing = Addressing.Implied, .cycles = 3 },
        0x68 => .{ .op = OpFast.OpPla, .addressing = Addressing.Implied, .cycles = 4 },
        0x28 => .{ .op = OpFast.OpPlp, .addressing = Addressing.Implied, .cycles = 4 },

        0x2a => .{ .op = OpFast.OpRol, .addressing = Addressing.Accumulator, .cycles = 2 },
        0x26 => .{ .op = OpFast.OpRol, .addressing = Addressing.ZeroPage, .cycles = 5 },
        0x36 => .{ .op = OpFast.OpRol, .addressing = Addressing.ZeroPageX, .cycles = 6 },
        0x2e => .{ .op = OpFast.OpRol, .addressing = Addressing.Absolute, .cycles = 6 },
        0x3e => .{ .op = OpFast.OpRol, .addressing = Addressing.AbsoluteX, .cycles = 7 },

        0x6a => .{ .op = OpFast.OpRor, .addressing = Addressing.Accumulator, .cycles = 2 },
        0x66 => .{ .op = OpFast.OpRor, .addressing = Addressing.ZeroPage, .cycles = 5 },
        0x76 => .{ .op = OpFast.OpRor, .addressing = Addressing.ZeroPageX, .cycles = 6 },
        0x6e => .{ .op = OpFast.OpRor, .addressing = Addressing.Absolute, .cycles = 6 },
        0x7e => .{ .op = OpFast.OpRor, .addressing = Addressing.AbsoluteX, .cycles = 7 },

        0x40 => .{ .op = OpFast.OpRti, .addressing = Addressing.Implied, .cycles = 6 },
        0x60 => .{ .op = OpFast.OpRts, .addressing = Addressing.Implied, .cycles = 6 },

        0xe9 => .{ .op = OpFast.OpSbc, .addressing = Addressing.Immediate, .cycles = 2 },
        0xe5 => .{ .op = OpFast.OpSbc, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0xf5 => .{ .op = OpFast.OpSbc, .addressing = Addressing.ZeroPageX, .cycles = 4 },
        0xed => .{ .op = OpFast.OpSbc, .addressing = Addressing.Absolute, .cycles = 4 },
        0xfd => .{ .op = OpFast.OpSbc, .addressing = Addressing.AbsoluteX, .cycles = 4, .var_cycles = true },
        0xf9 => .{ .op = OpFast.OpSbc, .addressing = Addressing.AbsoluteY, .cycles = 4, .var_cycles = true },
        0xe1 => .{ .op = OpFast.OpSbc, .addressing = Addressing.IndirectX, .cycles = 6 },
        0xf1 => .{ .op = OpFast.OpSbc, .addressing = Addressing.IndirectY, .cycles = 5, .var_cycles = true },

        0x38 => .{ .op = OpFast.OpSec, .addressing = Addressing.Implied, .cycles = 2 },
        0xf8 => .{ .op = OpFast.OpSed, .addressing = Addressing.Implied, .cycles = 2 },
        0x78 => .{ .op = OpFast.OpSei, .addressing = Addressing.Implied, .cycles = 2 },

        0x85 => .{ .op = OpFast.OpSta, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0x95 => .{ .op = OpFast.OpSta, .addressing = Addressing.ZeroPageX, .cycles = 4 },
        0x8d => .{ .op = OpFast.OpSta, .addressing = Addressing.Absolute, .cycles = 4 },
        0x9d => .{ .op = OpFast.OpSta, .addressing = Addressing.AbsoluteX, .cycles = 5 },
        0x99 => .{ .op = OpFast.OpSta, .addressing = Addressing.AbsoluteY, .cycles = 5 },
        0x81 => .{ .op = OpFast.OpSta, .addressing = Addressing.IndirectX, .cycles = 6 },
        0x91 => .{ .op = OpFast.OpSta, .addressing = Addressing.IndirectY, .cycles = 6 },

        0x86 => .{ .op = OpFast.OpStx, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0x96 => .{ .op = OpFast.OpStx, .addressing = Addressing.ZeroPageY, .cycles = 4 },
        0x8e => .{ .op = OpFast.OpStx, .addressing = Addressing.Absolute, .cycles = 4 },

        0x84 => .{ .op = OpFast.OpSty, .addressing = Addressing.ZeroPage, .cycles = 3 },
        0x94 => .{ .op = OpFast.OpSty, .addressing = Addressing.ZeroPageX, .cycles = 4 },
        0x8c => .{ .op = OpFast.OpSty, .addressing = Addressing.Absolute, .cycles = 4 },

        0xaa => .{ .op = OpFast.OpTax, .addressing = Addressing.Implied, .cycles = 2 },
        0xa8 => .{ .op = OpFast.OpTay, .addressing = Addressing.Implied, .cycles = 2 },
        0xba => .{ .op = OpFast.OpTsx, .addressing = Addressing.Implied, .cycles = 2 },
        0x8a => .{ .op = OpFast.OpTxa, .addressing = Addressing.Implied, .cycles = 2 },
        0x9a => .{ .op = OpFast.OpTxs, .addressing = Addressing.Implied, .cycles = 2 },
        0x98 => .{ .op = OpFast.OpTya, .addressing = Addressing.Implied, .cycles = 2 },

        else => .{ .op = OpFast.OpIll, .addressing = Addressing.Implied, .cycles = 0 },
    };
}

// TODO: finish later
// https://llx.com/Neil/a2/opcodes.html#insc02
fn decodeAccurate(opcode: u8) Instruction(.Accurate) {
    const OpAcc = Op(.Accurate);

    const aaa: u3 = @truncate(u3, opcode >> 5);
    const bbb: u3 = @truncate(u3, opcode >> 2);
    const cc: u2 = @truncate(u2, opcode);

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
