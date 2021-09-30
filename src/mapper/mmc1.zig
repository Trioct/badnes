const std = @import("std");
const Allocator = std.mem.Allocator;

const ines = @import("../ines.zig");

const console_ = @import("../console.zig");
const Config = console_.Config;
const Console = console_.Console;

const Cpu = @import("../cpu.zig").Cpu;

const GenericMapper = @import("../mapper.zig").GenericMapper;
const common = @import("common.zig");

const flags = @import("../flags.zig");

pub fn Mapper(comptime config: Config) type {
    const G = GenericMapper(config);
    return struct {
        const Self = @This();

        cpu: *Cpu(config),

        sram: common.Sram,
        prgs: common.Prgs,
        chrs: common.Chrs,
        mirroring: enum(u2) {
            one_screen_lower = 0,
            one_screen_upper = 1,
            vertical = 2,
            horizontal = 3,
        },

        last_write_cycle: usize = 0,
        shift_register: u4 = 0,
        write_count: u3 = 0,

        prg_bank_mode: enum {
            prg_switch_both,
            prg_fix_first,
            prg_fix_last,
        } = .prg_fix_last,

        chr_bank_mode: enum(u1) {
            chr_switch_both = 0,
            chr_switch_separate = 1,
        } = .chr_switch_both,

        prg_bank: u4 = 0,
        chr_bank0: u5 = 0,
        chr_bank1: u5 = 0,

        pub fn initMem(
            self: *Self,
            allocator: *Allocator,
            console: *Console(config),
            info: *ines.RomInfo,
        ) Allocator.Error!void {
            self.* = Self{
                .cpu = &console.cpu,

                .sram = try common.Sram.init(allocator, info.has_sram),
                .prgs = try common.Prgs.init(allocator, info.prg_rom),
                .chrs = try common.Chrs.init(allocator, info.chr_rom),
                .mirroring = @intToEnum(@TypeOf(self.mirroring), @enumToInt(info.mirroring)),
            };

            self.updatePrg();
            self.updateChr();
        }

        pub fn deinitMem(generic: G, allocator: *Allocator) void {
            const self = common.fromGeneric(Self, config, generic);

            self.sram.deinit(allocator);
            self.prgs.deinit(allocator);
            self.chrs.deinit(allocator);
            allocator.destroy(self);
        }

        pub fn mirrorNametable(generic: G, addr: u16) u12 {
            const self = common.fromGeneric(Self, config, generic);

            return switch (self.mirroring) {
                .one_screen_lower => @truncate(u12, addr & 0x3ff),
                .one_screen_upper => @truncate(u12, 0x400 | (addr & 0x3ff)),
                .vertical => @truncate(u12, addr & 0x7ff),
                .horizontal => @truncate(u12, addr & 0xbff),
            };
        }

        pub fn readPrg(generic: G, addr: u16) ?u8 {
            const self = common.fromGeneric(Self, config, generic);
            return switch (addr) {
                0x4020...0x5fff => null,
                0x6000...0x7fff => self.sram.read(addr),
                0x8000...0xffff => self.prgs.read(addr),
                else => unreachable,
            };
        }

        pub fn readChr(generic: G, addr: u16) u8 {
            const self = common.fromGeneric(Self, config, generic);
            return self.chrs.read(addr);
        }

        pub fn writePrg(generic: *G, addr: u16, val: u8) void {
            const self = common.fromGeneric(Self, config, generic.*);
            switch (addr) {
                0x4020...0x5fff => {},
                0x6000...0x7fff => self.sram.write(addr, val),
                0x8000...0xffff => self.writeRom(addr, val),
                else => unreachable,
            }
        }

        fn updatePrg(self: *Self) void {
            switch (self.prg_bank_mode) {
                .prg_switch_both => self.prgs.setConsecutiveBanks(0, 2, self.prg_bank),
                .prg_fix_first => {
                    self.prgs.setBank(0, 0);
                    self.prgs.setBank(1, self.prg_bank);
                },
                .prg_fix_last => {
                    self.prgs.setBank(0, self.prg_bank);
                    self.prgs.setBank(1, self.prgs.bankCount() - 1);
                },
            }
        }

        fn updateChr(self: *Self) void {
            switch (self.chr_bank_mode) {
                .chr_switch_both => {
                    self.chrs.setConsecutiveBanks(0, 2, self.chr_bank0 & 0x1e);
                },
                .chr_switch_separate => {
                    self.chrs.setBank(0, self.chr_bank0);
                    self.chrs.setBank(1, self.chr_bank1);
                },
            }
        }

        fn writeRom(self: *Self, addr: u16, val: u8) void {
            const temp = self.last_write_cycle;
            self.last_write_cycle = self.cpu.cycles;
            if (self.cpu.cycles == temp + 1) {
                return;
            }

            if (flags.getMaskBool(u8, val, 0x80)) {
                self.shift_register = 0;
                self.write_count = 0;

                self.prg_bank_mode = .prg_fix_last;
                self.updatePrg();

                return;
            }

            if (self.write_count != 4) {
                self.shift_register = (self.shift_register >> 1) | (@as(u4, @truncate(u1, val)) << 3);
                self.write_count += 1;
            } else {
                const final_val = @as(u5, self.shift_register) | (@as(u5, @truncate(u1, val)) << 4);
                switch (addr) {
                    0x8000...0x9fff => {
                        self.mirroring = @intToEnum(@TypeOf(self.mirroring), @truncate(u2, final_val));
                        self.prg_bank_mode = switch (@truncate(u2, final_val >> 2)) {
                            0, 1 => .prg_switch_both,
                            2 => .prg_fix_first,
                            3 => .prg_fix_last,
                        };
                        self.chr_bank_mode = @intToEnum(@TypeOf(self.chr_bank_mode), @truncate(u1, final_val >> 4));

                        self.updatePrg();
                        self.updateChr();
                    },
                    0xa000...0xbfff => {
                        self.chr_bank0 = final_val;
                        self.updateChr();
                    },
                    0xc000...0xdfff => {
                        self.chr_bank1 = final_val;
                        self.updateChr();
                    },
                    0xe000...0xffff => {
                        self.prg_bank = @truncate(u4, final_val);
                        self.updatePrg();

                        if (final_val & 0x10 != 0) {
                            std.log.err("Mapper 1 requesting ram when not implemented", .{});
                        }
                    },
                    else => unreachable,
                }

                self.shift_register = 0;
                self.write_count = 0;
            }
        }

        pub fn writeChr(generic: *G, addr: u16, val: u8) void {
            const self = common.fromGeneric(Self, config, generic.*);
            self.chrs.write(addr, val);
        }
    };
}
