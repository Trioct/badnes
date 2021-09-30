const std = @import("std");
const Cpu = @import("cpu.zig").Cpu;
const Precision = @import("console.zig").Precision;

pub fn Addressing(comptime precision: Precision) type {
    return switch (precision) {
        .fast => enum {
            accumulator,
            absolute,
            absoluteX,
            absoluteY,
            immediate,
            implied,
            indirect,
            indirectX,
            indirectY,
            relative,
            zeroPage,
            zeroPageX,
            zeroPageY,

            pub fn op_size(self: @This()) u2 {
                return switch (self) {
                    .accumulator => 1,
                    .absolute => 3,
                    .absoluteX => 3,
                    .absoluteY => 3,
                    .immediate => 2,
                    .implied => 1,
                    .indirect => 3,
                    .indirectX => 2,
                    .indirectY => 2,
                    .relative => 2,
                    .zeroPage => 2,
                    .zeroPageX => 2,
                    .zeroPageY => 2,
                };
            }
        },
        .accurate => enum {
            special,

            absolute,
            absoluteX,
            absoluteY,
            immediate,
            implied,
            indirectX,
            indirectY,
            relative,
            zeroPage,
            zeroPageX,
            zeroPageY,
        },
    };
}

pub fn Instruction(comptime precision: Precision) type {
    switch (precision) {
        .fast => return struct {
            op: Op(.fast),
            addressing: Addressing(.fast),
            cycles: u3,
            var_cycles: bool = false,

            pub const decode = decodeFast;
        },
        .accurate => return struct {
            op: Op(.accurate),
            addressing: Addressing(.accurate),
            access: Access,

            pub const decode = decodeAccurate;
        },
    }
}

// TODO: lut?
fn decodeFast(opcode: u8) Instruction(.fast) {
    const OpFast = Op(.fast);
    const AddrFast = Addressing(.fast);

    return switch (opcode) {
        0x69 => .{ .op = OpFast.op_adc, .addressing = AddrFast.immediate, .cycles = 2 },
        0x65 => .{ .op = OpFast.op_adc, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0x75 => .{ .op = OpFast.op_adc, .addressing = AddrFast.zeroPageX, .cycles = 4 },
        0x6d => .{ .op = OpFast.op_adc, .addressing = AddrFast.absolute, .cycles = 4 },
        0x7d => .{ .op = OpFast.op_adc, .addressing = AddrFast.absoluteX, .cycles = 4, .var_cycles = true },
        0x79 => .{ .op = OpFast.op_adc, .addressing = AddrFast.absoluteY, .cycles = 4, .var_cycles = true },
        0x61 => .{ .op = OpFast.op_adc, .addressing = AddrFast.indirectX, .cycles = 6 },
        0x71 => .{ .op = OpFast.op_adc, .addressing = AddrFast.indirectY, .cycles = 5, .var_cycles = true },

        0x29 => .{ .op = OpFast.op_and, .addressing = AddrFast.immediate, .cycles = 2 },
        0x25 => .{ .op = OpFast.op_and, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0x35 => .{ .op = OpFast.op_and, .addressing = AddrFast.zeroPageX, .cycles = 4 },
        0x2d => .{ .op = OpFast.op_and, .addressing = AddrFast.absolute, .cycles = 4 },
        0x3d => .{ .op = OpFast.op_and, .addressing = AddrFast.absoluteX, .cycles = 4, .var_cycles = true },
        0x39 => .{ .op = OpFast.op_and, .addressing = AddrFast.absoluteY, .cycles = 4, .var_cycles = true },
        0x21 => .{ .op = OpFast.op_and, .addressing = AddrFast.indirectX, .cycles = 6 },
        0x31 => .{ .op = OpFast.op_and, .addressing = AddrFast.indirectY, .cycles = 5, .var_cycles = true },

        0x0a => .{ .op = OpFast.op_asl, .addressing = AddrFast.accumulator, .cycles = 2 },
        0x06 => .{ .op = OpFast.op_asl, .addressing = AddrFast.zeroPage, .cycles = 5 },
        0x16 => .{ .op = OpFast.op_asl, .addressing = AddrFast.zeroPageX, .cycles = 6 },
        0x0e => .{ .op = OpFast.op_asl, .addressing = AddrFast.absolute, .cycles = 6 },
        0x1e => .{ .op = OpFast.op_asl, .addressing = AddrFast.absoluteX, .cycles = 7 },

        0x10 => .{ .op = OpFast.op_bpl, .addressing = AddrFast.relative, .cycles = 2 },
        0x30 => .{ .op = OpFast.op_bmi, .addressing = AddrFast.relative, .cycles = 2 },
        0x50 => .{ .op = OpFast.op_bvc, .addressing = AddrFast.relative, .cycles = 2 },
        0x70 => .{ .op = OpFast.op_bvs, .addressing = AddrFast.relative, .cycles = 2 },
        0x90 => .{ .op = OpFast.op_bcc, .addressing = AddrFast.relative, .cycles = 2 },
        0xb0 => .{ .op = OpFast.op_bcs, .addressing = AddrFast.relative, .cycles = 2 },
        0xd0 => .{ .op = OpFast.op_bne, .addressing = AddrFast.relative, .cycles = 2 },
        0xf0 => .{ .op = OpFast.op_beq, .addressing = AddrFast.relative, .cycles = 2 },

        0x24 => .{ .op = OpFast.op_bit, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0x2c => .{ .op = OpFast.op_bit, .addressing = AddrFast.absolute, .cycles = 4 },

        0x00 => .{ .op = OpFast.op_brk, .addressing = AddrFast.implied, .cycles = 7 },

        0x18 => .{ .op = OpFast.op_clc, .addressing = AddrFast.implied, .cycles = 2 },
        0xd8 => .{ .op = OpFast.op_cld, .addressing = AddrFast.implied, .cycles = 2 },
        0x58 => .{ .op = OpFast.op_cli, .addressing = AddrFast.implied, .cycles = 2 },
        0xb8 => .{ .op = OpFast.op_clv, .addressing = AddrFast.implied, .cycles = 2 },

        0xc9 => .{ .op = OpFast.op_cmp, .addressing = AddrFast.immediate, .cycles = 2 },
        0xc5 => .{ .op = OpFast.op_cmp, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0xd5 => .{ .op = OpFast.op_cmp, .addressing = AddrFast.zeroPageX, .cycles = 4 },
        0xcd => .{ .op = OpFast.op_cmp, .addressing = AddrFast.absolute, .cycles = 4 },
        0xdd => .{ .op = OpFast.op_cmp, .addressing = AddrFast.absoluteX, .cycles = 4, .var_cycles = true },
        0xd9 => .{ .op = OpFast.op_cmp, .addressing = AddrFast.absoluteY, .cycles = 4, .var_cycles = true },
        0xc1 => .{ .op = OpFast.op_cmp, .addressing = AddrFast.indirectX, .cycles = 6 },
        0xd1 => .{ .op = OpFast.op_cmp, .addressing = AddrFast.indirectY, .cycles = 5, .var_cycles = true },

        0xe0 => .{ .op = OpFast.op_cpx, .addressing = AddrFast.immediate, .cycles = 2 },
        0xe4 => .{ .op = OpFast.op_cpx, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0xec => .{ .op = OpFast.op_cpx, .addressing = AddrFast.absolute, .cycles = 4 },

        0xc0 => .{ .op = OpFast.op_cpy, .addressing = AddrFast.immediate, .cycles = 2 },
        0xc4 => .{ .op = OpFast.op_cpy, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0xcc => .{ .op = OpFast.op_cpy, .addressing = AddrFast.absolute, .cycles = 4 },

        0xc6 => .{ .op = OpFast.op_dec, .addressing = AddrFast.zeroPage, .cycles = 5 },
        0xd6 => .{ .op = OpFast.op_dec, .addressing = AddrFast.zeroPageX, .cycles = 6 },
        0xce => .{ .op = OpFast.op_dec, .addressing = AddrFast.absolute, .cycles = 6 },
        0xde => .{ .op = OpFast.op_dec, .addressing = AddrFast.absoluteX, .cycles = 7 },

        0xca => .{ .op = OpFast.op_dex, .addressing = AddrFast.implied, .cycles = 2 },
        0x88 => .{ .op = OpFast.op_dey, .addressing = AddrFast.implied, .cycles = 2 },

        0x49 => .{ .op = OpFast.op_eor, .addressing = AddrFast.immediate, .cycles = 2 },
        0x45 => .{ .op = OpFast.op_eor, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0x55 => .{ .op = OpFast.op_eor, .addressing = AddrFast.zeroPageX, .cycles = 4 },
        0x4d => .{ .op = OpFast.op_eor, .addressing = AddrFast.absolute, .cycles = 4 },
        0x5d => .{ .op = OpFast.op_eor, .addressing = AddrFast.absoluteX, .cycles = 4, .var_cycles = true },
        0x59 => .{ .op = OpFast.op_eor, .addressing = AddrFast.absoluteY, .cycles = 4, .var_cycles = true },
        0x41 => .{ .op = OpFast.op_eor, .addressing = AddrFast.indirectX, .cycles = 6 },
        0x51 => .{ .op = OpFast.op_eor, .addressing = AddrFast.indirectY, .cycles = 5, .var_cycles = true },

        0xe6 => .{ .op = OpFast.op_inc, .addressing = AddrFast.zeroPage, .cycles = 5 },
        0xf6 => .{ .op = OpFast.op_inc, .addressing = AddrFast.zeroPageX, .cycles = 6 },
        0xee => .{ .op = OpFast.op_inc, .addressing = AddrFast.absolute, .cycles = 6 },
        0xfe => .{ .op = OpFast.op_inc, .addressing = AddrFast.absoluteX, .cycles = 7 },

        0xe8 => .{ .op = OpFast.op_inx, .addressing = AddrFast.implied, .cycles = 2 },
        0xc8 => .{ .op = OpFast.op_iny, .addressing = AddrFast.implied, .cycles = 2 },

        0x4c => .{ .op = OpFast.op_jmp, .addressing = AddrFast.absolute, .cycles = 3 },
        0x6c => .{ .op = OpFast.op_jmp, .addressing = AddrFast.indirect, .cycles = 5 },

        0x20 => .{ .op = OpFast.op_jsr, .addressing = AddrFast.absolute, .cycles = 6 },

        0xa9 => .{ .op = OpFast.op_lda, .addressing = AddrFast.immediate, .cycles = 2 },
        0xa5 => .{ .op = OpFast.op_lda, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0xb5 => .{ .op = OpFast.op_lda, .addressing = AddrFast.zeroPageX, .cycles = 4 },
        0xad => .{ .op = OpFast.op_lda, .addressing = AddrFast.absolute, .cycles = 4 },
        0xbd => .{ .op = OpFast.op_lda, .addressing = AddrFast.absoluteX, .cycles = 4, .var_cycles = true },
        0xb9 => .{ .op = OpFast.op_lda, .addressing = AddrFast.absoluteY, .cycles = 4, .var_cycles = true },
        0xa1 => .{ .op = OpFast.op_lda, .addressing = AddrFast.indirectX, .cycles = 6 },
        0xb1 => .{ .op = OpFast.op_lda, .addressing = AddrFast.indirectY, .cycles = 5, .var_cycles = true },

        0xa2 => .{ .op = OpFast.op_ldx, .addressing = AddrFast.immediate, .cycles = 2 },
        0xa6 => .{ .op = OpFast.op_ldx, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0xb6 => .{ .op = OpFast.op_ldx, .addressing = AddrFast.zeroPageY, .cycles = 4 },
        0xae => .{ .op = OpFast.op_ldx, .addressing = AddrFast.absolute, .cycles = 4 },
        0xbe => .{ .op = OpFast.op_ldx, .addressing = AddrFast.absoluteY, .cycles = 4, .var_cycles = true },

        0xa0 => .{ .op = OpFast.op_ldy, .addressing = AddrFast.immediate, .cycles = 2 },
        0xa4 => .{ .op = OpFast.op_ldy, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0xb4 => .{ .op = OpFast.op_ldy, .addressing = AddrFast.zeroPageX, .cycles = 4 },
        0xac => .{ .op = OpFast.op_ldy, .addressing = AddrFast.absolute, .cycles = 4 },
        0xbc => .{ .op = OpFast.op_ldy, .addressing = AddrFast.absoluteX, .cycles = 4, .var_cycles = true },

        0x4a => .{ .op = OpFast.op_lsr, .addressing = AddrFast.accumulator, .cycles = 2 },
        0x46 => .{ .op = OpFast.op_lsr, .addressing = AddrFast.zeroPage, .cycles = 5 },
        0x56 => .{ .op = OpFast.op_lsr, .addressing = AddrFast.zeroPageX, .cycles = 6 },
        0x4e => .{ .op = OpFast.op_lsr, .addressing = AddrFast.absolute, .cycles = 6 },
        0x5e => .{ .op = OpFast.op_lsr, .addressing = AddrFast.absoluteX, .cycles = 7 },

        0xea => .{ .op = OpFast.op_nop, .addressing = AddrFast.implied, .cycles = 2 },

        0x09 => .{ .op = OpFast.op_ora, .addressing = AddrFast.immediate, .cycles = 2 },
        0x05 => .{ .op = OpFast.op_ora, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0x15 => .{ .op = OpFast.op_ora, .addressing = AddrFast.zeroPageX, .cycles = 4 },
        0x0d => .{ .op = OpFast.op_ora, .addressing = AddrFast.absolute, .cycles = 4 },
        0x1d => .{ .op = OpFast.op_ora, .addressing = AddrFast.absoluteX, .cycles = 4, .var_cycles = true },
        0x19 => .{ .op = OpFast.op_ora, .addressing = AddrFast.absoluteY, .cycles = 4, .var_cycles = true },
        0x01 => .{ .op = OpFast.op_ora, .addressing = AddrFast.indirectX, .cycles = 6 },
        0x11 => .{ .op = OpFast.op_ora, .addressing = AddrFast.indirectY, .cycles = 5, .var_cycles = true },

        0x48 => .{ .op = OpFast.op_pha, .addressing = AddrFast.implied, .cycles = 3 },
        0x08 => .{ .op = OpFast.op_php, .addressing = AddrFast.implied, .cycles = 3 },
        0x68 => .{ .op = OpFast.op_pla, .addressing = AddrFast.implied, .cycles = 4 },
        0x28 => .{ .op = OpFast.op_plp, .addressing = AddrFast.implied, .cycles = 4 },

        0x2a => .{ .op = OpFast.op_rol, .addressing = AddrFast.accumulator, .cycles = 2 },
        0x26 => .{ .op = OpFast.op_rol, .addressing = AddrFast.zeroPage, .cycles = 5 },
        0x36 => .{ .op = OpFast.op_rol, .addressing = AddrFast.zeroPageX, .cycles = 6 },
        0x2e => .{ .op = OpFast.op_rol, .addressing = AddrFast.absolute, .cycles = 6 },
        0x3e => .{ .op = OpFast.op_rol, .addressing = AddrFast.absoluteX, .cycles = 7 },

        0x6a => .{ .op = OpFast.op_ror, .addressing = AddrFast.accumulator, .cycles = 2 },
        0x66 => .{ .op = OpFast.op_ror, .addressing = AddrFast.zeroPage, .cycles = 5 },
        0x76 => .{ .op = OpFast.op_ror, .addressing = AddrFast.zeroPageX, .cycles = 6 },
        0x6e => .{ .op = OpFast.op_ror, .addressing = AddrFast.absolute, .cycles = 6 },
        0x7e => .{ .op = OpFast.op_ror, .addressing = AddrFast.absoluteX, .cycles = 7 },

        0x40 => .{ .op = OpFast.op_rti, .addressing = AddrFast.implied, .cycles = 6 },
        0x60 => .{ .op = OpFast.op_rts, .addressing = AddrFast.implied, .cycles = 6 },

        0xe9 => .{ .op = OpFast.op_sbc, .addressing = AddrFast.immediate, .cycles = 2 },
        0xe5 => .{ .op = OpFast.op_sbc, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0xf5 => .{ .op = OpFast.op_sbc, .addressing = AddrFast.zeroPageX, .cycles = 4 },
        0xed => .{ .op = OpFast.op_sbc, .addressing = AddrFast.absolute, .cycles = 4 },
        0xfd => .{ .op = OpFast.op_sbc, .addressing = AddrFast.absoluteX, .cycles = 4, .var_cycles = true },
        0xf9 => .{ .op = OpFast.op_sbc, .addressing = AddrFast.absoluteY, .cycles = 4, .var_cycles = true },
        0xe1 => .{ .op = OpFast.op_sbc, .addressing = AddrFast.indirectX, .cycles = 6 },
        0xf1 => .{ .op = OpFast.op_sbc, .addressing = AddrFast.indirectY, .cycles = 5, .var_cycles = true },

        0x38 => .{ .op = OpFast.op_sec, .addressing = AddrFast.implied, .cycles = 2 },
        0xf8 => .{ .op = OpFast.op_sed, .addressing = AddrFast.implied, .cycles = 2 },
        0x78 => .{ .op = OpFast.op_sei, .addressing = AddrFast.implied, .cycles = 2 },

        0x85 => .{ .op = OpFast.op_sta, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0x95 => .{ .op = OpFast.op_sta, .addressing = AddrFast.zeroPageX, .cycles = 4 },
        0x8d => .{ .op = OpFast.op_sta, .addressing = AddrFast.absolute, .cycles = 4 },
        0x9d => .{ .op = OpFast.op_sta, .addressing = AddrFast.absoluteX, .cycles = 5 },
        0x99 => .{ .op = OpFast.op_sta, .addressing = AddrFast.absoluteY, .cycles = 5 },
        0x81 => .{ .op = OpFast.op_sta, .addressing = AddrFast.indirectX, .cycles = 6 },
        0x91 => .{ .op = OpFast.op_sta, .addressing = AddrFast.indirectY, .cycles = 6 },

        0x86 => .{ .op = OpFast.op_stx, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0x96 => .{ .op = OpFast.op_stx, .addressing = AddrFast.zeroPageY, .cycles = 4 },
        0x8e => .{ .op = OpFast.op_stx, .addressing = AddrFast.absolute, .cycles = 4 },

        0x84 => .{ .op = OpFast.op_sty, .addressing = AddrFast.zeroPage, .cycles = 3 },
        0x94 => .{ .op = OpFast.op_sty, .addressing = AddrFast.zeroPageX, .cycles = 4 },
        0x8c => .{ .op = OpFast.op_sty, .addressing = AddrFast.absolute, .cycles = 4 },

        0xaa => .{ .op = OpFast.op_tax, .addressing = AddrFast.implied, .cycles = 2 },
        0xa8 => .{ .op = OpFast.op_tay, .addressing = AddrFast.implied, .cycles = 2 },
        0xba => .{ .op = OpFast.op_tsx, .addressing = AddrFast.implied, .cycles = 2 },
        0x8a => .{ .op = OpFast.op_txa, .addressing = AddrFast.implied, .cycles = 2 },
        0x9a => .{ .op = OpFast.op_txs, .addressing = AddrFast.implied, .cycles = 2 },
        0x98 => .{ .op = OpFast.op_tya, .addressing = AddrFast.implied, .cycles = 2 },

        else => .{ .op = OpFast.op_ill, .addressing = AddrFast.implied, .cycles = 0 },
    };
}

const op_lut = [256]Op(.accurate){
    .op_brk, .op_ora, .op_kil, .op_slo, .op_nop, .op_ora, .op_asl, .op_slo,
    .op_php, .op_ora, .op_asl, .op_anc, .op_nop, .op_ora, .op_asl, .op_slo,
    .op_bpl, .op_ora, .op_kil, .op_slo, .op_nop, .op_ora, .op_asl, .op_slo,
    .op_clc, .op_ora, .op_nop, .op_slo, .op_nop, .op_ora, .op_asl, .op_slo,
    .op_jsr, .op_and, .op_kil, .op_rla, .op_bit, .op_and, .op_rol, .op_rla,
    .op_plp, .op_and, .op_rol, .op_anc, .op_bit, .op_and, .op_rol, .op_rla,
    .op_bmi, .op_and, .op_kil, .op_rla, .op_nop, .op_and, .op_rol, .op_rla,
    .op_sec, .op_and, .op_nop, .op_rla, .op_nop, .op_and, .op_rol, .op_rla,
    .op_rti, .op_eor, .op_kil, .op_sre, .op_nop, .op_eor, .op_lsr, .op_sre,
    .op_pha, .op_eor, .op_lsr, .op_alr, .op_jmp, .op_eor, .op_lsr, .op_sre,
    .op_bvc, .op_eor, .op_kil, .op_sre, .op_nop, .op_eor, .op_lsr, .op_sre,
    .op_cli, .op_eor, .op_nop, .op_sre, .op_nop, .op_eor, .op_lsr, .op_sre,
    .op_rts, .op_adc, .op_kil, .op_rra, .op_nop, .op_adc, .op_ror, .op_rra,
    .op_pla, .op_adc, .op_ror, .op_arr, .op_jmp, .op_adc, .op_ror, .op_rra,
    .op_bvs, .op_adc, .op_kil, .op_rra, .op_nop, .op_adc, .op_ror, .op_rra,
    .op_sei, .op_adc, .op_nop, .op_rra, .op_nop, .op_adc, .op_ror, .op_rra,
    .op_nop, .op_sta, .op_nop, .op_sax, .op_sty, .op_sta, .op_stx, .op_sax,
    .op_dey, .op_nop, .op_txa, .op_xaa, .op_sty, .op_sta, .op_stx, .op_sax,
    .op_bcc, .op_sta, .op_kil, .op_ahx, .op_sty, .op_sta, .op_stx, .op_sax,
    .op_tya, .op_sta, .op_txs, .op_tas, .op_shy, .op_sta, .op_shx, .op_ahx,
    .op_ldy, .op_lda, .op_ldx, .op_lax, .op_ldy, .op_lda, .op_ldx, .op_lax,
    .op_tay, .op_lda, .op_tax, .op_lax, .op_ldy, .op_lda, .op_ldx, .op_lax,
    .op_bcs, .op_lda, .op_kil, .op_lax, .op_ldy, .op_lda, .op_ldx, .op_lax,
    .op_clv, .op_lda, .op_tsx, .op_las, .op_ldy, .op_lda, .op_ldx, .op_lax,
    .op_cpy, .op_cmp, .op_nop, .op_dcp, .op_cpy, .op_cmp, .op_dec, .op_dcp,
    .op_iny, .op_cmp, .op_dex, .op_axs, .op_cpy, .op_cmp, .op_dec, .op_dcp,
    .op_bne, .op_cmp, .op_kil, .op_dcp, .op_nop, .op_cmp, .op_dec, .op_dcp,
    .op_cld, .op_cmp, .op_nop, .op_dcp, .op_nop, .op_cmp, .op_dec, .op_dcp,
    .op_cpx, .op_sbc, .op_nop, .op_isc, .op_cpx, .op_sbc, .op_inc, .op_isc,
    .op_inx, .op_sbc, .op_nop, .op_sbc, .op_cpx, .op_sbc, .op_inc, .op_isc,
    .op_beq, .op_sbc, .op_kil, .op_isc, .op_nop, .op_sbc, .op_inc, .op_isc,
    .op_sed, .op_sbc, .op_nop, .op_isc, .op_nop, .op_sbc, .op_inc, .op_isc,
};

const addr_lut = blk: {
    const intToEnum = [12]Addressing(.accurate){
        .special, // = 0
        .absolute, // = 1
        .absoluteX, // = 2
        .absoluteY, // = 3
        .immediate, // = 4
        .implied, // = 5
        .indirectX, // = 6
        .indirectY, // = 7
        .relative, // = 8
        .zeroPage, // = 9
        .zeroPageX, // = 10
        .zeroPageY, // = 11
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

    var result = [1]Addressing(.accurate){undefined} ** 256;
    for (numbered) |n, i| {
        result[i] = intToEnum[n];
    }
    break :blk result;
};

/// Most instructions fall into the category of
/// read only, read-modify-write, or read-write
pub const Access = enum {
    special,

    read,
    rmw,
    write,
};

const access_lut = blk: {
    @setEvalBranchQuota(2000);
    var result = [1]Access{undefined} ** 256;

    for (result) |*r, i| {
        const access = switch (addr_lut[i]) {
            .special => .special,
            .implied, .immediate, .relative => .read,
            else => switch (op_lut[i]) {
                .op_jmp => .special,

                .op_lda, .op_ldx, .op_ldy, .op_eor, .op_and, .op_ora, .op_adc => .read,
                .op_sbc, .op_cmp, .op_cpx, .op_cpy, .op_bit, .op_lax, .op_nop => .read,
                .op_las, .op_tas => .read,

                .op_asl, .op_lsr, .op_rol, .op_ror, .op_inc, .op_dec, .op_slo => .rmw,
                .op_sre, .op_rla, .op_rra, .op_isc, .op_dcp => .rmw,

                .op_sta, .op_stx, .op_sty, .op_sax, .op_ahx, .op_shx, .op_shy => .write,
                else => @compileError("Haven't implemented op " ++ opToString(op_lut[i])),
            },
        };
        r.* = access;
    }

    break :blk result;
};

fn decodeAccurate(opcode: u8) Instruction(.accurate) {
    return Instruction(.accurate){
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
            _ = std.ascii.upperString(idx[0..], enum_fields[i].name[3..]);
        }
        break :blk arr;
    };
    return enum_strs[@enumToInt(op)][0..];
}

pub fn Op(comptime precision: Precision) type {
    const Ill = enum {
        op_ill,
    };

    // zig fmt: off
    const Documented = enum {
        op_adc, op_and, op_asl, op_bpl, op_bmi, op_bvc, op_bvs, op_bcc,
        op_bcs, op_bne, op_beq, op_bit, op_brk, op_clc, op_cld, op_cli,
        op_clv, op_cmp, op_cpx, op_cpy, op_dec, op_dex, op_dey, op_eor,
        op_inc, op_inx, op_iny, op_jmp, op_jsr, op_lda, op_ldx, op_ldy,
        op_lsr, op_nop, op_ora, op_pha, op_php, op_pla, op_plp, op_rol,
        op_ror, op_rti, op_rts, op_sbc, op_sec, op_sed, op_sei, op_sta,
        op_stx, op_sty, op_tax, op_tay, op_tsx, op_txa, op_txs, op_tya,
    };
    // zig fmt: on

    const Undocumented = enum {
        /// SAH, SHA
        op_ahx,
        /// ASR
        op_alr,
        /// AAC
        op_anc,
        op_arr,
        /// SBX
        op_axs,
        /// DCM
        op_dcp,
        /// INS, ISB
        op_isc,
        op_kil,
        /// LAE, LAR, AST
        op_las,
        op_lax,
        op_rla,
        op_rra,
        /// AAX, AXS
        op_sax,
        /// SXA, SXH, XAS
        op_shx,
        op_shy,
        /// ASO
        op_slo,
        /// LSE
        op_sre,
        /// SHS, SSH, XAS
        op_tas,
        /// ANE, AXA
        op_xaa,
    };

    switch (precision) {
        .fast => return MergedEnum(Ill, Documented),
        .accurate => return MergedEnum(Documented, Undocumented),
    }
}
