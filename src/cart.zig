const std = @import("std");
const Allocator = std.mem.Allocator;

const ines = @import("ines.zig");
const mapper = @import("mapper.zig");
const GenericMapper = mapper.GenericMapper;

const console_ = @import("console.zig");
const Config = console_.Config;
const Console = console_.Console;

pub fn Cart(comptime config: Config) type {
    return struct {
        const Self = @This();
        mapper: GenericMapper(config),
        rom_loaded: bool,

        pub fn init() Self {
            return Self{
                .mapper = undefined,
                .rom_loaded = false,
            };
        }

        pub fn deinit(self: Self, allocator: *Allocator) void {
            if (!self.rom_loaded) {
                return;
            }
            self.mapper.deinit(allocator);
        }

        pub fn loadRom(self: *Self, allocator: *Allocator, console: *Console(config), info: *ines.RomInfo) !void {
            if (self.rom_loaded) {
                self.mapper.deinit(allocator);
            }
            self.rom_loaded = true;
            const inits = comptime blk: {
                break :blk mapper.inits(config);
            };
            self.mapper = try inits[info.mapper](allocator, console, info);
            info.prg_rom = null;
            info.chr_rom = null;
        }

        pub fn mirrorNametable(self: Self, addr: u16) u12 {
            return self.mapper.mirrorNametable(addr);
        }

        pub fn readPrg(self: Self, addr: u16) u8 {
            return self.mapper.readPrg(addr);
        }

        pub fn writePrg(self: *Self, addr: u16, val: u8) void {
            _ = self;
            _ = addr;
            _ = val;
        }

        pub const peekChr = readChr;

        pub fn readChr(self: Self, addr: u16) u8 {
            return self.mapper.readChr(addr);
        }

        pub fn writeChr(self: *Self, addr: u16, val: u8) void {
            return self.mapper.writeChr(addr, val);
        }
    };
}
