const std = @import("std");
const Allocator = std.mem.Allocator;

const Console = @import("console.zig").Console;
const ines = @import("ines.zig");
const mapper = @import("mapper.zig");
const GenericMapper = mapper.GenericMapper;

pub const Cart = struct {
    mapper: GenericMapper,
    rom_loaded: bool,

    pub fn init() Cart {
        return Cart{
            .mapper = undefined,
            .rom_loaded = false,
        };
    }

    pub fn deinit(self: Cart, allocator: *Allocator) void {
        if (!self.rom_loaded) {
            return;
        }
        self.mapper.deinit(allocator);
    }

    pub fn loadRom(self: *Cart, allocator: *Allocator, console: *Console, info: *ines.RomInfo) !void {
        if (self.rom_loaded) {
            self.mapper.deinit(allocator);
        }
        self.rom_loaded = true;
        self.mapper = try mapper.inits[info.mapper](allocator, console, info);
        info.prg_rom = null;
        info.chr_rom = null;
    }

    pub const peekPrg = readPrg;

    pub fn readPrg(self: Cart, addr: u16) u8 {
        return self.mapper.readPrg(addr);
    }

    pub fn writePrg(self: *Cart, addr: u16, val: u8) void {
        _ = self;
        _ = addr;
        _ = val;
    }

    pub const peekChr = readChr;

    pub fn readChr(self: Cart, addr: u16) u8 {
        return self.mapper.readChr(addr);
    }

    pub fn writeChr(self: *Cart, addr: u16, val: u8) void {
        return self.mapper.writeChr(addr, val);
    }
};
