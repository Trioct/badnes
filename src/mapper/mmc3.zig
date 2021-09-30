const std = @import("std");
const Allocator = std.mem.Allocator;

const ines = @import("../ines.zig");

const console_ = @import("../console.zig");
const Config = console_.Config;
const Console = console_.Console;

const Cpu = @import("../cpu.zig").Cpu;
const Ppu = @import("../ppu.zig").Ppu;

const GenericMapper = @import("../mapper.zig").GenericMapper;
const common = @import("common.zig");

pub fn Mapper(comptime config: Config) type {
    const G = GenericMapper(config);
    return struct {
        const Self = @This();

        cpu: *Cpu(config),
        ppu: *Ppu(config),

        sram: common.Sram,
        prgs: common.BankSwitcher(0x2000, 4),
        chrs: common.BankSwitcher(0x400, 8),
        mirroring: ines.Mirroring,

        prg_bank_mode: enum(u1) {
            Swap8000 = 0,
            SwapC000 = 1,
        } = .Swap8000,

        chr_bank_mode: enum(u1) {
            /// Two 2kb followed by four 1kb banks
            TwoThenFour = 0,
            /// Four 1kb followed by two 2kb banks
            FourThenTwo = 1,
        } = .TwoThenFour,

        bank_registers: [8]u8 = std.mem.zeroes([8]u8),
        select_register: u3 = 0,

        irq_enabled: bool = false,
        irq_latch: u8 = 0,
        irq_counter: u8 = 0,
        ppu_a12_low_cycles: u2 = 0,

        pub fn initMem(
            self: *Self,
            allocator: *Allocator,
            console: *Console(config),
            info: *ines.RomInfo,
        ) Allocator.Error!void {
            std.debug.assert(info.prg_rom_mul_16kb >= 2);

            self.* = Self{
                .cpu = &console.cpu,
                .ppu = &console.ppu,

                .sram = try common.Sram.init(allocator, info.has_sram),
                .prgs = try common.BankSwitcher(0x2000, 4).init(allocator, info.prg_rom),
                .chrs = try common.BankSwitcher(0x400, 8).init(allocator, info.chr_rom),
                .mirroring = info.mirroring,
            };

            self.updatePrg();
            self.updateChr();
        }

        pub fn deinitMem(generic: G, allocator: *Allocator) void {
            const self = common.fromGeneric(Self, config, generic);

            self.prgs.deinit(allocator);
            self.chrs.deinit(allocator);
            allocator.destroy(self);
        }

        pub fn cpuCycled(generic: *G) void {
            const self = common.fromGeneric(Self, config, generic.*);

            // we're waiting for 3 cpu cycles where vram_addr & 0x1000 == 0
            // and then a cycle where it goes high
            if (self.ppu.vram_addr.value & 0x1000 == 0) {
                self.ppu_a12_low_cycles +|= 1;
            } else if (self.ppu_a12_low_cycles == 3) {
                std.debug.print("high: ({}, {}) -> {x:0>4}\n", .{
                    self.ppu.scanline,
                    self.ppu.cycle,
                    self.ppu.vram_addr.value,
                });
            }
        }

        pub fn mirrorNametable(generic: G, addr: u16) u12 {
            const self = common.fromGeneric(Self, config, generic);
            return common.mirrorNametable(self.mirroring, addr);
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
            self.prgs.setBank(1, self.bank_registers[7]);
            self.prgs.setBank(3, self.prgs.bankCount() - 1);

            switch (self.prg_bank_mode) {
                .Swap8000 => {
                    self.prgs.setBank(0, self.bank_registers[6]);
                    self.prgs.setBank(2, self.prgs.bankCount() - 2);
                },
                .SwapC000 => {
                    self.prgs.setBank(0, self.prgs.bankCount() - 2);
                    self.prgs.setBank(2, self.bank_registers[6]);
                },
            }
        }

        fn updateChr(self: *Self) void {
            switch (self.chr_bank_mode) {
                .TwoThenFour => {
                    self.chrs.setConsecutiveBanks(0, 2, self.bank_registers[0]);
                    self.chrs.setConsecutiveBanks(2, 2, self.bank_registers[1]);
                    self.chrs.setBank(4, self.bank_registers[2]);
                    self.chrs.setBank(5, self.bank_registers[3]);
                    self.chrs.setBank(6, self.bank_registers[4]);
                    self.chrs.setBank(7, self.bank_registers[5]);
                },
                .FourThenTwo => {
                    self.chrs.setBank(0, self.bank_registers[2]);
                    self.chrs.setBank(1, self.bank_registers[3]);
                    self.chrs.setBank(2, self.bank_registers[4]);
                    self.chrs.setBank(3, self.bank_registers[5]);
                    self.chrs.setConsecutiveBanks(4, 2, self.bank_registers[0]);
                    self.chrs.setConsecutiveBanks(6, 2, self.bank_registers[1]);
                },
            }
        }

        fn writeRomEven(self: *Self, addr: u16, val: u8) void {
            switch (addr) {
                0x8000...0x9ffe => {
                    self.select_register = @truncate(u3, val);
                    self.prg_bank_mode = @intToEnum(@TypeOf(self.prg_bank_mode), @truncate(u1, val >> 6));
                    self.chr_bank_mode = @intToEnum(@TypeOf(self.chr_bank_mode), @truncate(u1, val >> 7));

                    self.updatePrg();
                    self.updateChr();
                },
                0xa000...0xbffe => if (self.mirroring != .FourScreen) {
                    self.mirroring = @intToEnum(ines.Mirroring, @truncate(u1, val));
                },
                0xc000...0xdffe => self.irq_latch = val,
                0xe000...0xfffe => self.irq_enabled = false,
                else => unreachable,
            }
        }

        fn writeRomOdd(self: *Self, addr: u16, val: u8) void {
            switch (addr) {
                0x8001...0x9fff => {
                    const fixed_val = switch (self.select_register) {
                        0, 1 => val & 0xfe,
                        6, 7 => val & 0x3f,
                        else => val,
                    };
                    self.bank_registers[self.select_register] = fixed_val;

                    self.updateChr();
                    self.updatePrg();
                },
                0xa001...0xbfff => {
                    self.sram.writable = val & 0x40 != 0;
                    self.sram.enabled = val & 0x80 != 0;
                },
                0xc001...0xdfff => self.irq_counter = self.irq_latch,
                0xe001...0xffff => self.irq_enabled = true,
                else => unreachable,
            }
        }

        fn writeRom(self: *Self, addr: u16, val: u8) void {
            if (addr & 1 == 0) {
                self.writeRomEven(addr, val);
            } else {
                self.writeRomOdd(addr, val);
            }
        }

        pub fn writeChr(generic: *G, addr: u16, val: u8) void {
            const self = common.fromGeneric(Self, config, generic.*);
            self.chrs.write(addr, val);
        }
    };
}
