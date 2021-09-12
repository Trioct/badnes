const std = @import("std");
const Allocator = std.mem.Allocator;

const ines = @import("ines.zig");

pub const Cart = struct {
    rom_loaded: bool,
    rom: Rom,
    chr_rom_is_ram: bool,

    pub const Rom = struct {
        prg: []u8,
        chr: []u8,

        pub fn deinit(self: Rom, allocator: *Allocator) void {
            allocator.free(self.prg);
            allocator.free(self.chr);
        }
    };

    pub fn init() Cart {
        return Cart{
            .rom_loaded = false,
            .rom = Rom{
                .prg = undefined,
                .chr = undefined,
            },
            .chr_rom_is_ram = undefined,
        };
    }

    pub fn deinit(self: Cart, allocator: *Allocator) void {
        if (!self.rom_loaded) {
            return;
        }
        self.rom.deinit(allocator);
    }

    pub fn loadRom(self: *Cart, allocator: *Allocator, info: *ines.RomInfo) !void {
        if (self.rom_loaded) {
            self.rom.deinit(allocator);
        }
        self.rom_loaded = true;
        self.rom.prg = info.prg_rom.?;
        if (info.chr_rom) |chr| {
            self.rom.chr = chr;
            self.chr_rom_is_ram = false;
        } else {
            self.rom.chr = try allocator.alloc(u8, 0x2000);
            self.chr_rom_is_ram = true;
        }
        info.prg_rom = null;
        info.chr_rom = null;
    }

    pub const peekPrg = readPrg;

    pub fn readPrg(self: Cart, address: u16) u8 {
        return self.rom.prg[address & 0x7fff];
    }

    pub fn writePrg(self: *Cart, address: u16, val: u8) void {
        _ = self;
        _ = address;
        _ = val;
    }

    pub const peekChr = readChr;

    pub fn readChr(self: Cart, address: u16) u8 {
        return self.rom.chr[address & 0x1fff];
    }

    pub fn writeChr(self: *Cart, address: u16, val: u8) void {
        if (self.chr_rom_is_ram) {
            self.rom.chr[address & 0x1fff] = val;
        }
    }
};
