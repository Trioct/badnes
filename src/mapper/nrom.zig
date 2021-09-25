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

        prgs: common.Prgs,
        chrs: common.Chrs,
        mirroring: ines.Mirroring,

        pub fn initMem(
            self: *Self,
            allocator: *Allocator,
            _: *Console(config),
            info: *ines.RomInfo,
        ) Allocator.Error!void {
            self.prgs = try common.Prgs.init(allocator, info.prg_rom);
            self.chrs = try common.Chrs.init(allocator, info.chr_rom);
            self.mirroring = info.mirroring;
        }

        pub fn deinitMem(generic: G, allocator: *Allocator) void {
            const self = common.fromGeneric(Self, config, generic);

            self.prgs.deinit(allocator);
            self.chrs.deinit(allocator);
            allocator.destroy(self);
        }

        pub fn mirrorNametable(generic: G, addr: u16) u12 {
            const self = common.fromGeneric(Self, config, generic);
            return common.mirrorNametable(self.mirroring, addr);
        }

        pub fn readPrg(generic: G, addr: u16) u8 {
            const self = common.fromGeneric(Self, config, generic);
            if (addr >= 0x8000) {
                return self.prgs.read(addr);
            } else {
                return 0;
            }
        }

        pub fn readChr(generic: G, addr: u16) u8 {
            const self = common.fromGeneric(Self, config, generic);
            return self.chrs.read(addr);
        }

        pub fn writePrg(_: *G, _: u16, _: u8) void {}

        pub fn writeChr(generic: *G, addr: u16, val: u8) void {
            const self = common.fromGeneric(Self, config, generic.*);
            self.chrs.write(addr, val);
        }
    };
}
