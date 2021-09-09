const std = @import("std");
const Allocator = std.mem.Allocator;

const Ines = @import("ines.zig");

pub const Cart = struct {
    rom_loaded: bool,
    rom: Rom,

    pub const Rom = struct {
        prg: []const u8,
        chr: ?[]const u8,

        pub fn deinit(self: Rom, allocator: *Allocator) void {
            allocator.free(self.prg);
            if (self.chr) |chr| {
                allocator.free(chr);
            }
        }
    };

    pub fn init() Cart {
        return Cart{
            .rom_loaded = false,
            .rom = undefined,
        };
    }

    pub fn deinit(self: Cart, allocator: *Allocator) void {
        if (!self.rom_loaded) {
            return;
        }
        self.rom.deinit(allocator);
    }

    pub fn loadRom(self: *Cart, allocator: *Allocator, info: *Ines.RomInfo) void {
        if (self.rom_loaded) {
            self.rom.deinit(allocator);
        }
        self.rom_loaded = true;
        self.rom = info.rom.?;
        info.rom = null;
    }

    pub fn getPtr(self: Cart, address: u16) *const u8 {
        return &self.rom.prg[address & 0x3fff];
    }

    pub fn read(self: Cart, address: u16) u8 {
        return self.getPtr(address).*;
    }

    pub fn write(self: *Cart, address: u16, val: u8) void {
        _ = self;
        _ = address;
        _ = val;
    }
};
