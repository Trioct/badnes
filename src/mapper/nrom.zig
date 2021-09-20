const std = @import("std");
const Allocator = std.mem.Allocator;

const ines = @import("../ines.zig");

const console_ = @import("../console.zig");
const Config = console_.Config;
const Console = console_.Console;

const GenericMapper = @import("../mapper.zig").GenericMapper;
const common = @import("common.zig");

pub fn Mapper(comptime config: Config) type {
    const G = GenericMapper(config);
    return struct {
        const Self = @This();

        prg: []u8,
        chr: common.Chr,
        mirroring: ines.Mirroring,

        fn fromGeneric(generic: G) *Self {
            return @ptrCast(*Self, generic.mapper_ptr);
        }

        pub fn initMem(
            self: *Self,
            allocator: *Allocator,
            _: *Console(config),
            info: *ines.RomInfo,
        ) Allocator.Error!void {
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
            self.chr = try common.Chr.init(allocator, info.chr_rom);
            self.mirroring = info.mirroring;
        }

        pub fn deinitMem(generic: G, allocator: *Allocator) void {
            const self = Self.fromGeneric(generic);
            allocator.free(self.prg);
            self.chr.deinit(allocator);
            allocator.destroy(self);
        }

        pub fn mirrorNametable(generic: G, addr: u16) u12 {
            const self = Self.fromGeneric(generic);
            return common.mirrorNametable(self.mirroring, addr);
        }

        pub fn readPrg(generic: G, addr: u16) u8 {
            const self = Self.fromGeneric(generic);
            return self.prg[addr & 0x7fff];
        }

        pub fn readChr(generic: G, addr: u16) u8 {
            const self = Self.fromGeneric(generic);
            return self.chr.read(addr);
        }

        pub fn writePrg(_: *G, _: u16, _: u8) void {}

        pub fn writeChr(generic: *G, addr: u16, val: u8) void {
            const self = Self.fromGeneric(generic.*);
            self.chr.write(addr, val);
        }
    };
}
