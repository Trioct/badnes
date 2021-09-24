const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Precision = @import("console.zig").Precision;

pub fn Addressing(comptime precision: Precision) type {
    return switch (precision) {
        .Fast => enum {
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

            pub fn op_size(self: @This()) u2 {
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
        },
        .Accurate => enum {
            Special,

            Absolute,
            AbsoluteX,
            AbsoluteY,
            Immediate,
            Implied,
            IndirectX,
            IndirectY,
            Relative,
            ZeroPage,
            ZeroPageX,
            ZeroPageY,
        },
    };
}

pub fn Instruction(comptime precision: Precision) type {
    switch (precision) {
        .Fast => return struct {
            op: Op(.Fast),
            addressing: Addressing(.Fast),
            cycles: u3,
            var_cycles: bool = false,

            pub const decode = decodeFast;
        },
        .Accurate => return struct {
            op: Op(.Accurate),
            addressing: Addressing(.Accurate),
            access: Access,

            pub const decode = decodeAccurate;
        },
    }
}

// TODO: lut?
fn decodeFast(opcode: u8) Instruction(.Fast) {
    const OpFast = Op(.Fast);
    const AddrFast = Addressing(.Fast);

    return switch (opcode) {
        0x69 => .{ .op = OpFast.OpAdc, .addressing = AddrFast.Immediate, .cycles = 2 },
        0x65 => .{ .op = OpFast.OpAdc, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0x75 => .{ .op = OpFast.OpAdc, .addressing = AddrFast.ZeroPageX, .cycles = 4 },
        0x6d => .{ .op = OpFast.OpAdc, .addressing = AddrFast.Absolute, .cycles = 4 },
        0x7d => .{ .op = OpFast.OpAdc, .addressing = AddrFast.AbsoluteX, .cycles = 4, .var_cycles = true },
        0x79 => .{ .op = OpFast.OpAdc, .addressing = AddrFast.AbsoluteY, .cycles = 4, .var_cycles = true },
        0x61 => .{ .op = OpFast.OpAdc, .addressing = AddrFast.IndirectX, .cycles = 6 },
        0x71 => .{ .op = OpFast.OpAdc, .addressing = AddrFast.IndirectY, .cycles = 5, .var_cycles = true },

        0x29 => .{ .op = OpFast.OpAnd, .addressing = AddrFast.Immediate, .cycles = 2 },
        0x25 => .{ .op = OpFast.OpAnd, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0x35 => .{ .op = OpFast.OpAnd, .addressing = AddrFast.ZeroPageX, .cycles = 4 },
        0x2d => .{ .op = OpFast.OpAnd, .addressing = AddrFast.Absolute, .cycles = 4 },
        0x3d => .{ .op = OpFast.OpAnd, .addressing = AddrFast.AbsoluteX, .cycles = 4, .var_cycles = true },
        0x39 => .{ .op = OpFast.OpAnd, .addressing = AddrFast.AbsoluteY, .cycles = 4, .var_cycles = true },
        0x21 => .{ .op = OpFast.OpAnd, .addressing = AddrFast.IndirectX, .cycles = 6 },
        0x31 => .{ .op = OpFast.OpAnd, .addressing = AddrFast.IndirectY, .cycles = 5, .var_cycles = true },

        0x0a => .{ .op = OpFast.OpAsl, .addressing = AddrFast.Accumulator, .cycles = 2 },
        0x06 => .{ .op = OpFast.OpAsl, .addressing = AddrFast.ZeroPage, .cycles = 5 },
        0x16 => .{ .op = OpFast.OpAsl, .addressing = AddrFast.ZeroPageX, .cycles = 6 },
        0x0e => .{ .op = OpFast.OpAsl, .addressing = AddrFast.Absolute, .cycles = 6 },
        0x1e => .{ .op = OpFast.OpAsl, .addressing = AddrFast.AbsoluteX, .cycles = 7 },

        0x10 => .{ .op = OpFast.OpBpl, .addressing = AddrFast.Relative, .cycles = 2 },
        0x30 => .{ .op = OpFast.OpBmi, .addressing = AddrFast.Relative, .cycles = 2 },
        0x50 => .{ .op = OpFast.OpBvc, .addressing = AddrFast.Relative, .cycles = 2 },
        0x70 => .{ .op = OpFast.OpBvs, .addressing = AddrFast.Relative, .cycles = 2 },
        0x90 => .{ .op = OpFast.OpBcc, .addressing = AddrFast.Relative, .cycles = 2 },
        0xb0 => .{ .op = OpFast.OpBcs, .addressing = AddrFast.Relative, .cycles = 2 },
        0xd0 => .{ .op = OpFast.OpBne, .addressing = AddrFast.Relative, .cycles = 2 },
        0xf0 => .{ .op = OpFast.OpBeq, .addressing = AddrFast.Relative, .cycles = 2 },

        0x24 => .{ .op = OpFast.OpBit, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0x2c => .{ .op = OpFast.OpBit, .addressing = AddrFast.Absolute, .cycles = 4 },

        0x00 => .{ .op = OpFast.OpBrk, .addressing = AddrFast.Implied, .cycles = 7 },

        0x18 => .{ .op = OpFast.OpClc, .addressing = AddrFast.Implied, .cycles = 2 },
        0xd8 => .{ .op = OpFast.OpCld, .addressing = AddrFast.Implied, .cycles = 2 },
        0x58 => .{ .op = OpFast.OpCli, .addressing = AddrFast.Implied, .cycles = 2 },
        0xb8 => .{ .op = OpFast.OpClv, .addressing = AddrFast.Implied, .cycles = 2 },

        0xc9 => .{ .op = OpFast.OpCmp, .addressing = AddrFast.Immediate, .cycles = 2 },
        0xc5 => .{ .op = OpFast.OpCmp, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0xd5 => .{ .op = OpFast.OpCmp, .addressing = AddrFast.ZeroPageX, .cycles = 4 },
        0xcd => .{ .op = OpFast.OpCmp, .addressing = AddrFast.Absolute, .cycles = 4 },
        0xdd => .{ .op = OpFast.OpCmp, .addressing = AddrFast.AbsoluteX, .cycles = 4, .var_cycles = true },
        0xd9 => .{ .op = OpFast.OpCmp, .addressing = AddrFast.AbsoluteY, .cycles = 4, .var_cycles = true },
        0xc1 => .{ .op = OpFast.OpCmp, .addressing = AddrFast.IndirectX, .cycles = 6 },
        0xd1 => .{ .op = OpFast.OpCmp, .addressing = AddrFast.IndirectY, .cycles = 5, .var_cycles = true },

        0xe0 => .{ .op = OpFast.OpCpx, .addressing = AddrFast.Immediate, .cycles = 2 },
        0xe4 => .{ .op = OpFast.OpCpx, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0xec => .{ .op = OpFast.OpCpx, .addressing = AddrFast.Absolute, .cycles = 4 },

        0xc0 => .{ .op = OpFast.OpCpy, .addressing = AddrFast.Immediate, .cycles = 2 },
        0xc4 => .{ .op = OpFast.OpCpy, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0xcc => .{ .op = OpFast.OpCpy, .addressing = AddrFast.Absolute, .cycles = 4 },

        0xc6 => .{ .op = OpFast.OpDec, .addressing = AddrFast.ZeroPage, .cycles = 5 },
        0xd6 => .{ .op = OpFast.OpDec, .addressing = AddrFast.ZeroPageX, .cycles = 6 },
        0xce => .{ .op = OpFast.OpDec, .addressing = AddrFast.Absolute, .cycles = 6 },
        0xde => .{ .op = OpFast.OpDec, .addressing = AddrFast.AbsoluteX, .cycles = 7 },

        0xca => .{ .op = OpFast.OpDex, .addressing = AddrFast.Implied, .cycles = 2 },
        0x88 => .{ .op = OpFast.OpDey, .addressing = AddrFast.Implied, .cycles = 2 },

        0x49 => .{ .op = OpFast.OpEor, .addressing = AddrFast.Immediate, .cycles = 2 },
        0x45 => .{ .op = OpFast.OpEor, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0x55 => .{ .op = OpFast.OpEor, .addressing = AddrFast.ZeroPageX, .cycles = 4 },
        0x4d => .{ .op = OpFast.OpEor, .addressing = AddrFast.Absolute, .cycles = 4 },
        0x5d => .{ .op = OpFast.OpEor, .addressing = AddrFast.AbsoluteX, .cycles = 4, .var_cycles = true },
        0x59 => .{ .op = OpFast.OpEor, .addressing = AddrFast.AbsoluteY, .cycles = 4, .var_cycles = true },
        0x41 => .{ .op = OpFast.OpEor, .addressing = AddrFast.IndirectX, .cycles = 6 },
        0x51 => .{ .op = OpFast.OpEor, .addressing = AddrFast.IndirectY, .cycles = 5, .var_cycles = true },

        0xe6 => .{ .op = OpFast.OpInc, .addressing = AddrFast.ZeroPage, .cycles = 5 },
        0xf6 => .{ .op = OpFast.OpInc, .addressing = AddrFast.ZeroPageX, .cycles = 6 },
        0xee => .{ .op = OpFast.OpInc, .addressing = AddrFast.Absolute, .cycles = 6 },
        0xfe => .{ .op = OpFast.OpInc, .addressing = AddrFast.AbsoluteX, .cycles = 7 },

        0xe8 => .{ .op = OpFast.OpInx, .addressing = AddrFast.Implied, .cycles = 2 },
        0xc8 => .{ .op = OpFast.OpIny, .addressing = AddrFast.Implied, .cycles = 2 },

        0x4c => .{ .op = OpFast.OpJmp, .addressing = AddrFast.Absolute, .cycles = 3 },
        0x6c => .{ .op = OpFast.OpJmp, .addressing = AddrFast.Indirect, .cycles = 5 },

        0x20 => .{ .op = OpFast.OpJsr, .addressing = AddrFast.Absolute, .cycles = 6 },

        0xa9 => .{ .op = OpFast.OpLda, .addressing = AddrFast.Immediate, .cycles = 2 },
        0xa5 => .{ .op = OpFast.OpLda, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0xb5 => .{ .op = OpFast.OpLda, .addressing = AddrFast.ZeroPageX, .cycles = 4 },
        0xad => .{ .op = OpFast.OpLda, .addressing = AddrFast.Absolute, .cycles = 4 },
        0xbd => .{ .op = OpFast.OpLda, .addressing = AddrFast.AbsoluteX, .cycles = 4, .var_cycles = true },
        0xb9 => .{ .op = OpFast.OpLda, .addressing = AddrFast.AbsoluteY, .cycles = 4, .var_cycles = true },
        0xa1 => .{ .op = OpFast.OpLda, .addressing = AddrFast.IndirectX, .cycles = 6 },
        0xb1 => .{ .op = OpFast.OpLda, .addressing = AddrFast.IndirectY, .cycles = 5, .var_cycles = true },

        0xa2 => .{ .op = OpFast.OpLdx, .addressing = AddrFast.Immediate, .cycles = 2 },
        0xa6 => .{ .op = OpFast.OpLdx, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0xb6 => .{ .op = OpFast.OpLdx, .addressing = AddrFast.ZeroPageY, .cycles = 4 },
        0xae => .{ .op = OpFast.OpLdx, .addressing = AddrFast.Absolute, .cycles = 4 },
        0xbe => .{ .op = OpFast.OpLdx, .addressing = AddrFast.AbsoluteY, .cycles = 4, .var_cycles = true },

        0xa0 => .{ .op = OpFast.OpLdy, .addressing = AddrFast.Immediate, .cycles = 2 },
        0xa4 => .{ .op = OpFast.OpLdy, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0xb4 => .{ .op = OpFast.OpLdy, .addressing = AddrFast.ZeroPageX, .cycles = 4 },
        0xac => .{ .op = OpFast.OpLdy, .addressing = AddrFast.Absolute, .cycles = 4 },
        0xbc => .{ .op = OpFast.OpLdy, .addressing = AddrFast.AbsoluteX, .cycles = 4, .var_cycles = true },

        0x4a => .{ .op = OpFast.OpLsr, .addressing = AddrFast.Accumulator, .cycles = 2 },
        0x46 => .{ .op = OpFast.OpLsr, .addressing = AddrFast.ZeroPage, .cycles = 5 },
        0x56 => .{ .op = OpFast.OpLsr, .addressing = AddrFast.ZeroPageX, .cycles = 6 },
        0x4e => .{ .op = OpFast.OpLsr, .addressing = AddrFast.Absolute, .cycles = 6 },
        0x5e => .{ .op = OpFast.OpLsr, .addressing = AddrFast.AbsoluteX, .cycles = 7 },

        0xea => .{ .op = OpFast.OpNop, .addressing = AddrFast.Implied, .cycles = 2 },

        0x09 => .{ .op = OpFast.OpOra, .addressing = AddrFast.Immediate, .cycles = 2 },
        0x05 => .{ .op = OpFast.OpOra, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0x15 => .{ .op = OpFast.OpOra, .addressing = AddrFast.ZeroPageX, .cycles = 4 },
        0x0d => .{ .op = OpFast.OpOra, .addressing = AddrFast.Absolute, .cycles = 4 },
        0x1d => .{ .op = OpFast.OpOra, .addressing = AddrFast.AbsoluteX, .cycles = 4, .var_cycles = true },
        0x19 => .{ .op = OpFast.OpOra, .addressing = AddrFast.AbsoluteY, .cycles = 4, .var_cycles = true },
        0x01 => .{ .op = OpFast.OpOra, .addressing = AddrFast.IndirectX, .cycles = 6 },
        0x11 => .{ .op = OpFast.OpOra, .addressing = AddrFast.IndirectY, .cycles = 5, .var_cycles = true },

        0x48 => .{ .op = OpFast.OpPha, .addressing = AddrFast.Implied, .cycles = 3 },
        0x08 => .{ .op = OpFast.OpPhp, .addressing = AddrFast.Implied, .cycles = 3 },
        0x68 => .{ .op = OpFast.OpPla, .addressing = AddrFast.Implied, .cycles = 4 },
        0x28 => .{ .op = OpFast.OpPlp, .addressing = AddrFast.Implied, .cycles = 4 },

        0x2a => .{ .op = OpFast.OpRol, .addressing = AddrFast.Accumulator, .cycles = 2 },
        0x26 => .{ .op = OpFast.OpRol, .addressing = AddrFast.ZeroPage, .cycles = 5 },
        0x36 => .{ .op = OpFast.OpRol, .addressing = AddrFast.ZeroPageX, .cycles = 6 },
        0x2e => .{ .op = OpFast.OpRol, .addressing = AddrFast.Absolute, .cycles = 6 },
        0x3e => .{ .op = OpFast.OpRol, .addressing = AddrFast.AbsoluteX, .cycles = 7 },

        0x6a => .{ .op = OpFast.OpRor, .addressing = AddrFast.Accumulator, .cycles = 2 },
        0x66 => .{ .op = OpFast.OpRor, .addressing = AddrFast.ZeroPage, .cycles = 5 },
        0x76 => .{ .op = OpFast.OpRor, .addressing = AddrFast.ZeroPageX, .cycles = 6 },
        0x6e => .{ .op = OpFast.OpRor, .addressing = AddrFast.Absolute, .cycles = 6 },
        0x7e => .{ .op = OpFast.OpRor, .addressing = AddrFast.AbsoluteX, .cycles = 7 },

        0x40 => .{ .op = OpFast.OpRti, .addressing = AddrFast.Implied, .cycles = 6 },
        0x60 => .{ .op = OpFast.OpRts, .addressing = AddrFast.Implied, .cycles = 6 },

        0xe9 => .{ .op = OpFast.OpSbc, .addressing = AddrFast.Immediate, .cycles = 2 },
        0xe5 => .{ .op = OpFast.OpSbc, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0xf5 => .{ .op = OpFast.OpSbc, .addressing = AddrFast.ZeroPageX, .cycles = 4 },
        0xed => .{ .op = OpFast.OpSbc, .addressing = AddrFast.Absolute, .cycles = 4 },
        0xfd => .{ .op = OpFast.OpSbc, .addressing = AddrFast.AbsoluteX, .cycles = 4, .var_cycles = true },
        0xf9 => .{ .op = OpFast.OpSbc, .addressing = AddrFast.AbsoluteY, .cycles = 4, .var_cycles = true },
        0xe1 => .{ .op = OpFast.OpSbc, .addressing = AddrFast.IndirectX, .cycles = 6 },
        0xf1 => .{ .op = OpFast.OpSbc, .addressing = AddrFast.IndirectY, .cycles = 5, .var_cycles = true },

        0x38 => .{ .op = OpFast.OpSec, .addressing = AddrFast.Implied, .cycles = 2 },
        0xf8 => .{ .op = OpFast.OpSed, .addressing = AddrFast.Implied, .cycles = 2 },
        0x78 => .{ .op = OpFast.OpSei, .addressing = AddrFast.Implied, .cycles = 2 },

        0x85 => .{ .op = OpFast.OpSta, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0x95 => .{ .op = OpFast.OpSta, .addressing = AddrFast.ZeroPageX, .cycles = 4 },
        0x8d => .{ .op = OpFast.OpSta, .addressing = AddrFast.Absolute, .cycles = 4 },
        0x9d => .{ .op = OpFast.OpSta, .addressing = AddrFast.AbsoluteX, .cycles = 5 },
        0x99 => .{ .op = OpFast.OpSta, .addressing = AddrFast.AbsoluteY, .cycles = 5 },
        0x81 => .{ .op = OpFast.OpSta, .addressing = AddrFast.IndirectX, .cycles = 6 },
        0x91 => .{ .op = OpFast.OpSta, .addressing = AddrFast.IndirectY, .cycles = 6 },

        0x86 => .{ .op = OpFast.OpStx, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0x96 => .{ .op = OpFast.OpStx, .addressing = AddrFast.ZeroPageY, .cycles = 4 },
        0x8e => .{ .op = OpFast.OpStx, .addressing = AddrFast.Absolute, .cycles = 4 },

        0x84 => .{ .op = OpFast.OpSty, .addressing = AddrFast.ZeroPage, .cycles = 3 },
        0x94 => .{ .op = OpFast.OpSty, .addressing = AddrFast.ZeroPageX, .cycles = 4 },
        0x8c => .{ .op = OpFast.OpSty, .addressing = AddrFast.Absolute, .cycles = 4 },

        0xaa => .{ .op = OpFast.OpTax, .addressing = AddrFast.Implied, .cycles = 2 },
        0xa8 => .{ .op = OpFast.OpTay, .addressing = AddrFast.Implied, .cycles = 2 },
        0xba => .{ .op = OpFast.OpTsx, .addressing = AddrFast.Implied, .cycles = 2 },
        0x8a => .{ .op = OpFast.OpTxa, .addressing = AddrFast.Implied, .cycles = 2 },
        0x9a => .{ .op = OpFast.OpTxs, .addressing = AddrFast.Implied, .cycles = 2 },
        0x98 => .{ .op = OpFast.OpTya, .addressing = AddrFast.Implied, .cycles = 2 },

        else => .{ .op = OpFast.OpIll, .addressing = AddrFast.Implied, .cycles = 0 },
    };
}

const op_lut = [256]Op(.Accurate){
    .OpBrk, .OpOra, .OpKil, .OpSlo, .OpNop, .OpOra, .OpAsl, .OpSlo,
    .OpPhp, .OpOra, .OpAsl, .OpAnc, .OpNop, .OpOra, .OpAsl, .OpSlo,
    .OpBpl, .OpOra, .OpKil, .OpSlo, .OpNop, .OpOra, .OpAsl, .OpSlo,
    .OpClc, .OpOra, .OpNop, .OpSlo, .OpNop, .OpOra, .OpAsl, .OpSlo,
    .OpJsr, .OpAnd, .OpKil, .OpRla, .OpBit, .OpAnd, .OpRol, .OpRla,
    .OpPlp, .OpAnd, .OpRol, .OpAnc, .OpBit, .OpAnd, .OpRol, .OpRla,
    .OpBmi, .OpAnd, .OpKil, .OpRla, .OpNop, .OpAnd, .OpRol, .OpRla,
    .OpSec, .OpAnd, .OpNop, .OpRla, .OpNop, .OpAnd, .OpRol, .OpRla,
    .OpRti, .OpEor, .OpKil, .OpSre, .OpNop, .OpEor, .OpLsr, .OpSre,
    .OpPha, .OpEor, .OpLsr, .OpAlr, .OpJmp, .OpEor, .OpLsr, .OpSre,
    .OpBvc, .OpEor, .OpKil, .OpSre, .OpNop, .OpEor, .OpLsr, .OpSre,
    .OpCli, .OpEor, .OpNop, .OpSre, .OpNop, .OpEor, .OpLsr, .OpSre,
    .OpRts, .OpAdc, .OpKil, .OpRra, .OpNop, .OpAdc, .OpRor, .OpRra,
    .OpPla, .OpAdc, .OpRor, .OpArr, .OpJmp, .OpAdc, .OpRor, .OpRra,
    .OpBvs, .OpAdc, .OpKil, .OpRra, .OpNop, .OpAdc, .OpRor, .OpRra,
    .OpSei, .OpAdc, .OpNop, .OpRra, .OpNop, .OpAdc, .OpRor, .OpRra,
    .OpNop, .OpSta, .OpNop, .OpSax, .OpSty, .OpSta, .OpStx, .OpSax,
    .OpDey, .OpNop, .OpTxa, .OpXaa, .OpSty, .OpSta, .OpStx, .OpSax,
    .OpBcc, .OpSta, .OpKil, .OpAhx, .OpSty, .OpSta, .OpStx, .OpSax,
    .OpTya, .OpSta, .OpTxs, .OpTas, .OpShy, .OpSta, .OpShx, .OpAhx,
    .OpLdy, .OpLda, .OpLdx, .OpLax, .OpLdy, .OpLda, .OpLdx, .OpLax,
    .OpTay, .OpLda, .OpTax, .OpLax, .OpLdy, .OpLda, .OpLdx, .OpLax,
    .OpBcs, .OpLda, .OpKil, .OpLax, .OpLdy, .OpLda, .OpLdx, .OpLax,
    .OpClv, .OpLda, .OpTsx, .OpLas, .OpLdy, .OpLda, .OpLdx, .OpLax,
    .OpCpy, .OpCmp, .OpNop, .OpDcp, .OpCpy, .OpCmp, .OpDec, .OpDcp,
    .OpIny, .OpCmp, .OpDex, .OpAxs, .OpCpy, .OpCmp, .OpDec, .OpDcp,
    .OpBne, .OpCmp, .OpKil, .OpDcp, .OpNop, .OpCmp, .OpDec, .OpDcp,
    .OpCld, .OpCmp, .OpNop, .OpDcp, .OpNop, .OpCmp, .OpDec, .OpDcp,
    .OpCpx, .OpSbc, .OpNop, .OpIsc, .OpCpx, .OpSbc, .OpInc, .OpIsc,
    .OpInx, .OpSbc, .OpNop, .OpSbc, .OpCpx, .OpSbc, .OpInc, .OpIsc,
    .OpBeq, .OpSbc, .OpKil, .OpIsc, .OpNop, .OpSbc, .OpInc, .OpIsc,
    .OpSed, .OpSbc, .OpNop, .OpIsc, .OpNop, .OpSbc, .OpInc, .OpIsc,
};

const addr_lut = blk: {
    const intToEnum = [12]Addressing(.Accurate){
        .Special, // = 0
        .Absolute, // = 1
        .AbsoluteX, // = 2
        .AbsoluteY, // = 3
        .Immediate, // = 4
        .Implied, // = 5
        .IndirectX, // = 6
        .IndirectY, // = 7
        .Relative, // = 8
        .ZeroPage, // = 9
        .ZeroPageX, // = 10
        .ZeroPageY, // = 11
    };
    const numbered = [256]comptime_int{
        0, 6, 5, 6, 9,  9,  9,  9,  0, 4, 5, 4, 1, 1, 1, 1,
        8, 7, 5, 7, 10, 10, 10, 10, 5, 3, 5, 3, 2, 2, 2, 2,

        0, 6, 5, 6, 9,  9,  9,  9,  0, 4, 5, 4, 1, 1, 1, 1,
        8, 7, 5, 7, 10, 10, 10, 10, 5, 3, 5, 3, 2, 2, 2, 2,

        0, 6, 5, 6, 9,  9,  9,  9,  0, 4, 5, 4, 0, 1, 1, 1,
        8, 7, 5, 7, 10, 10, 10, 10, 5, 3, 5, 3, 2, 2, 2, 2,

        0, 6, 5, 6, 9,  9,  9,  9,  0, 4, 5, 4, 0, 1, 1, 1,
        8, 7, 5, 7, 10, 10, 10, 10, 5, 3, 5, 3, 2, 2, 2, 2,

        4, 6, 4, 6, 9,  9,  9,  9,  5, 4, 5, 4, 1, 1, 1, 1,
        8, 7, 5, 7, 10, 10, 11, 11, 5, 3, 5, 3, 2, 2, 3, 3,

        4, 6, 4, 6, 9,  9,  9,  9,  5, 4, 5, 4, 1, 1, 1, 1,
        8, 7, 5, 7, 10, 10, 11, 11, 5, 3, 5, 3, 2, 2, 3, 3,

        4, 6, 4, 6, 9,  9,  9,  9,  5, 4, 5, 4, 1, 1, 1, 1,
        8, 7, 5, 7, 10, 10, 10, 10, 5, 3, 5, 3, 2, 2, 2, 2,

        4, 6, 4, 6, 9,  9,  9,  9,  5, 4, 5, 4, 1, 1, 1, 1,
        8, 7, 5, 7, 10, 10, 10, 10, 5, 3, 5, 3, 2, 2, 2, 2,
    };

    var result = [1]Addressing(.Accurate){undefined} ** 256;
    for (numbered) |n, i| {
        result[i] = intToEnum[n];
    }
    break :blk result;
};

/// Most instructions fall into the category of
/// read only, read-modify-write, or read-write
pub const Access = enum {
    Special,

    Read,
    Rmw,
    Write,
};

const access_lut = blk: {
    @setEvalBranchQuota(2000);
    var result = [1]Access{undefined} ** 256;

    for (result) |*r, i| {
        const access = switch (addr_lut[i]) {
            .Special => .Special,
            .Implied, .Immediate, .Relative => .Read,
            else => switch (op_lut[i]) {
                .OpJmp => .Special,

                .OpLda, .OpLdx, .OpLdy, .OpEor, .OpAnd, .OpOra, .OpAdc => .Read,
                .OpSbc, .OpCmp, .OpCpx, .OpCpy, .OpBit, .OpLax, .OpNop => .Read,
                .OpLas, .OpTas => .Read,

                .OpAsl, .OpLsr, .OpRol, .OpRor, .OpInc, .OpDec, .OpSlo => .Rmw,
                .OpSre, .OpRla, .OpRra, .OpIsc, .OpDcp => .Rmw,

                .OpSta, .OpStx, .OpSty, .OpSax, .OpAhx, .OpShx, .OpShy => .Write,
                else => @compileError("Haven't implemented op " ++ opToString(op_lut[i])),
            },
        };
        r.* = access;
    }

    break :blk result;
};

fn decodeAccurate(opcode: u8) Instruction(.Accurate) {
    return Instruction(.Accurate){
        .op = op_lut[opcode],
        .addressing = addr_lut[opcode],
        .access = access_lut[opcode],
    };
}

/// Merge T2 fields into T1
/// Surely there must be a stdlib function for this?
fn MergedEnum(comptime T1: type, comptime T2: type) type {
    const type_info1 = @typeInfo(T1);
    const type_info2 = @typeInfo(T2);

    const total_fields = type_info1.Enum.fields.len + type_info2.Enum.fields.len;

    var fields = [1]std.builtin.TypeInfo.EnumField{undefined} ** total_fields;
    var i: usize = 0;
    for (type_info1.Enum.fields) |field| {
        fields[i] = .{ .name = field.name, .value = i };
        i += 1;
    }

    for (type_info2.Enum.fields) |field| {
        fields[i] = .{ .name = field.name, .value = i };
        i += 1;
    }

    const bits = std.math.log2_int_ceil(usize, total_fields);

    return @Type(.{ .Enum = .{
        .layout = .Auto,
        .tag_type = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = bits } }),
        .fields = fields[0..],
        .decls = ([0]std.builtin.TypeInfo.Declaration{})[0..],
        .is_exhaustive = true,
    } });
}

pub fn opToString(op: anytype) []const u8 {
    const enum_strs = comptime blk: {
        const enum_fields = @typeInfo(@TypeOf(op)).Enum.fields;
        var arr = [_]([3]u8){undefined} ** enum_fields.len;
        for (arr) |*idx, i| {
            _ = std.ascii.upperString(idx[0..], enum_fields[i].name[2..]);
        }
        break :blk arr;
    };
    return enum_strs[@enumToInt(op)][0..];
}

pub fn Op(comptime precision: Precision) type {
    const Ill = enum {
        OpIll,
    };

    const Documented = enum {
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
    };

    const Undocumented = enum {
        /// SAH, SHA
        OpAhx,
        /// ASR
        OpAlr,
        /// AAC
        OpAnc,
        OpArr,
        /// SBX
        OpAxs,
        /// DCM
        OpDcp,
        /// INS, ISB
        OpIsc,
        OpKil,
        /// LAE, LAR, AST
        OpLas,
        OpLax,
        OpRla,
        OpRra,
        /// AAX, AXS
        OpSax,
        /// SXA, SXH, XAS
        OpShx,
        OpShy,
        /// ASO
        OpSlo,
        /// LSE
        OpSre,
        /// SHS, SSH, XAS
        OpTas,
        /// ANE, AXA
        OpXaa,
    };

    switch (precision) {
        .Fast => return MergedEnum(Ill, Documented),
        .Accurate => return MergedEnum(Documented, Undocumented),
    }
}
