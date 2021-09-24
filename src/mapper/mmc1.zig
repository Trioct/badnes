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

        prgs: common.Prgs,
        chrs: common.Chrs,
        mirroring: enum(u2) {
            OneScreenLower,
            OneScreenUpper,
            Vertical,
            Horizontal,
        },

        last_write_cycle: usize,
        shift_register: u4,
        write_count: u3,

        prg_bank_mode: enum {
            PrgSwitchBoth,
            PrgFixFirst,
            PrgFixLast,
        },

        chr_bank_mode: enum(u1) {
            ChrSwitchBoth,
            ChrSwitchSeparate,
        },

        pub fn initMem(
            self: *Self,
            allocator: *Allocator,
            console: *Console(config),
            info: *ines.RomInfo,
        ) Allocator.Error!void {
            self.cpu = &console.cpu;

            self.prgs = try common.Prgs.init(allocator, info.prg_rom);
            self.chrs = try common.Chrs.init(allocator, info.chr_rom);
            self.mirroring = @intToEnum(@TypeOf(self.mirroring), @enumToInt(info.mirroring));

            self.last_write_cycle = 0;
            self.shift_register = 0;
            self.write_count = 0;

            self.prg_bank_mode = .PrgFixLast;
            self.chr_bank_mode = .ChrSwitchBoth;

            self.setPrg(0);
        }

        pub fn deinitMem(generic: G, allocator: *Allocator) void {
            const self = common.fromGeneric(Self, config, generic);

            self.prgs.deinit(allocator);
            self.chrs.deinit(allocator);
            allocator.destroy(self);
        }

        fn setPrg(self: *Self, bank: u4) void {
            switch (self.prg_bank_mode) {
                .PrgSwitchBoth => self.prgs.setBothBanks(bank),
                .PrgFixFirst => {
                    self.prgs.setBank(0, 0);
                    self.prgs.setBank(1, bank);
                },
                .PrgFixLast => {
                    self.prgs.setBank(0, bank);
                    self.prgs.setBank(1, self.prgs.lastBankIndex());
                },
            }
        }

        pub fn mirrorNametable(generic: G, addr: u16) u12 {
            const self = common.fromGeneric(Self, config, generic);

            return switch (self.mirroring) {
                .OneScreenLower => @truncate(u12, addr & 0x3ff),
                .OneScreenUpper => @truncate(u12, 0x400 | (addr & 0x3ff)),
                .Vertical => @truncate(u12, addr & 0x7ff),
                .Horizontal => @truncate(u12, addr & 0xbff),
            };
        }

        pub fn readPrg(generic: G, addr: u16) u8 {
            const self = common.fromGeneric(Self, config, generic);
            return self.prgs.read(addr);
        }

        pub fn readChr(generic: G, addr: u16) u8 {
            const self = common.fromGeneric(Self, config, generic);
            return self.chrs.read(addr);
        }

        pub fn writePrg(generic: *G, addr: u16, val: u8) void {
            const self = common.fromGeneric(Self, config, generic.*);

            const temp = self.last_write_cycle;
            self.last_write_cycle = self.cpu.cycles;
            if (self.cpu.cycles == temp + 1) {
                return;
            }

            if (flags.getMaskBool(u8, val, 0x80)) {
                self.shift_register = 0;
                self.write_count = 0;
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
                            0, 1 => .PrgSwitchBoth,
                            2 => .PrgFixFirst,
                            3 => .PrgFixLast,
                        };
                        self.chr_bank_mode = @intToEnum(@TypeOf(self.chr_bank_mode), @truncate(u1, final_val >> 4));
                        self.chrs.setBank(1, 0);
                    },
                    0xa000...0xbfff => {
                        switch (self.chr_bank_mode) {
                            .ChrSwitchBoth => {
                                self.chrs.setBothBanks(self.shift_register & ~@as(u5, 1));
                            },
                            .ChrSwitchSeparate => {
                                self.chrs.setBank(0, final_val);
                            },
                        }
                    },
                    0xc000...0xdfff => {
                        switch (self.chr_bank_mode) {
                            .ChrSwitchBoth => {},
                            .ChrSwitchSeparate => {
                                self.chrs.setBank(1, final_val);
                            },
                        }
                    },
                    0xe000...0xffff => {
                        self.setPrg(@truncate(u4, final_val));
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
