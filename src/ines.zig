// https://wiki.nesdev.com/w/index.php?title=INES

const std = @import("std");
const fs = std.fs;
const io = std.io;

const Rom = @import("cart.zig").Cart.Rom;

const Allocator = std.mem.Allocator;

pub const InesError = error{
    MissingMagic,
    UnexpectedEndOfPrgRom,
    UnexpectedEndOfChrRom,
};

pub const Mirroring = enum {
    Horizontal,
    Vertical,
    FourScreen,
};

pub const RomInfo = struct {
    prg_rom: ?[]u8,
    chr_rom: ?[]u8,

    prg_rom_mul_16kb: u8,
    prg_ram_mul_8kb: ?u8,
    chr_header_byte: ChrHeaderByte,

    mirroring: Mirroring,
    has_trainer: bool,
    mapper: u8, //TODO: Make enum

    const ChrHeaderByte = union(enum) {
        UsesChrRam,
        Mul8Kb: u8,
    };

    pub fn deinit(self: RomInfo, allocator: *Allocator) void {
        if (self.prg_rom) |prg| {
            allocator.free(prg);
        }
        if (self.chr_rom) |chr| {
            allocator.free(chr);
        }
    }

    pub fn readFile(allocator: *Allocator, path: []const u8) !RomInfo {
        std.log.info("Loading rom at path \"{s}\"", .{path});

        const file = try fs.cwd().openFile(path, .{});
        defer file.close();

        return RomInfo.readReader(allocator, file.reader());
    }

    pub fn readReader(allocator: *Allocator, reader: anytype) !RomInfo {
        const magic = "NES\x1a";
        if (!(try reader.isBytes(magic[0..]))) {
            return InesError.MissingMagic;
        }

        const prg_rom_mul_16kb = try reader.readByte();
        const chr_header_byte = blk: {
            const byte = try reader.readByte();
            if (byte == 0) {
                break :blk .UsesChrRam;
            } else {
                break :blk RomInfo.ChrHeaderByte{ .Mul8Kb = byte };
            }
        };

        const flags6 = try reader.readByte();
        const mirroring = blk: {
            const bit0 = flags6 & 0b01;
            const bit1 = (flags6 >> 2) & 0b10;
            break :blk @intToEnum(Mirroring, bit0 | bit1);
        };
        const has_prg_ram = (flags6 >> 1) & 1 == 1;
        const has_trainer = (flags6 >> 2) & 1 == 1;

        const flags7 = try reader.readByte();
        const mapper = (flags7 & 0xf) | (flags6 >> 4);

        const flags8 = try reader.readByte();
        const prg_ram_mul_8kb = if (has_prg_ram) @maximum(flags8, 1) else null;

        try reader.skipBytes(7 + if (has_trainer) @as(usize, 512) else 0, .{});

        const prg_rom_size = @as(usize, prg_rom_mul_16kb) * 1024 * 16;
        const prg_rom = try allocator.alloc(u8, prg_rom_size);
        errdefer allocator.free(prg_rom);
        if ((try reader.readAll(prg_rom)) != prg_rom_size) {
            return InesError.UnexpectedEndOfPrgRom;
        }

        const chr_rom = switch (chr_header_byte) {
            .UsesChrRam => null,
            .Mul8Kb => |chr_rom_mul_8kb| blk: {
                const chr_rom_size = @as(usize, chr_rom_mul_8kb) * 1024 * 8;
                const rom = try allocator.alloc(u8, chr_rom_size);
                errdefer allocator.free(rom);
                if ((try reader.readAll(rom)) != chr_rom_size) {
                    return InesError.UnexpectedEndOfChrRom;
                }
                break :blk rom;
            },
        };

        return RomInfo{
            .prg_rom = prg_rom,
            .chr_rom = chr_rom,

            .prg_rom_mul_16kb = prg_rom_mul_16kb,
            .prg_ram_mul_8kb = prg_ram_mul_8kb,
            .chr_header_byte = chr_header_byte,

            .mirroring = mirroring,
            .has_trainer = has_trainer,
            .mapper = mapper,
        };
    }
};

const testing = std.testing;

test "Parse INES 1.0" {
    const info = try RomInfo.readFile(testing.allocator, "roms/tests/nestest.nes");
    defer info.deinit(testing.allocator);

    try testing.expectEqual(@as(u8, 1), info.prg_rom_mul_16kb);
    try testing.expectEqual(@as(?u8, null), info.prg_ram_mul_8kb);
    try testing.expectEqual(RomInfo.ChrHeaderByte{ .Mul8Kb = 1 }, info.chr_header_byte);
    try testing.expectEqual(RomInfo.Mirroring.Horizontal, info.mirroring);
    try testing.expectEqual(false, info.has_trainer);
    try testing.expectEqual(@as(u8, 0), info.mapper);
}
