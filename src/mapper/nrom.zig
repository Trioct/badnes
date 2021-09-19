const std = @import("std");
const Allocator = std.mem.Allocator;

const ines = @import("../ines.zig");
const Console = @import("../console.zig").Console;

const GenericMapper = @import("../mapper.zig").GenericMapper;
const Chr = @import("common.zig").Chr;

pub const Mapper = struct {
    prg: []u8,
    chr: Chr,

    fn fromGeneric(generic: GenericMapper) *Mapper {
        return @ptrCast(*Mapper, generic.mapper_ptr);
    }

    pub fn initMem(self: *Mapper, allocator: *Allocator, _: *Console, info: *ines.RomInfo) Allocator.Error!void {
        if (info.prg_rom) |prg| {
            switch (info.prg_rom_mul_16kb) {
                1 => {
                    self.prg = try allocator.alloc(u8, 0x8000);
                    std.mem.copy(u8, self.prg[0..0x4000], prg[0..]);
                    std.mem.copy(u8, self.prg[0x4000..0x8000], prg[0..]);
                    allocator.free(prg);
                },
                2 => self.prg = prg,
                else => @panic("Invalid prg pages for nrom"),
            }
        }
        self.chr = try Chr.init(allocator, info.chr_rom);
    }

    pub fn deinitMem(generic: GenericMapper, allocator: *Allocator) void {
        const self = Mapper.fromGeneric(generic);
        allocator.free(self.prg);
        self.chr.deinit(allocator);
        allocator.destroy(self);
    }

    pub fn readPrg(generic: GenericMapper, addr: u16) u8 {
        const self = Mapper.fromGeneric(generic);
        return self.prg[addr & 0x7fff];
    }

    pub fn readChr(generic: GenericMapper, addr: u16) u8 {
        const self = Mapper.fromGeneric(generic);
        return self.chr.read(addr & 0x1fff);
    }

    pub fn writePrg(_: *GenericMapper, _: u16, _: u8) void {}

    pub fn writeChr(generic: *GenericMapper, addr: u16, val: u8) void {
        const self = Mapper.fromGeneric(generic.*);
        self.chr.write(addr, val);
    }
};
