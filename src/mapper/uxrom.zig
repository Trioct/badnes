const std = @import("std");
const Allocator = std.mem.Allocator;

const ines = @import("../ines.zig");

const console_ = @import("../console.zig");
const Config = console_.Config;
const Console = console_.Console;

const GenericMapper = @import("../mapper.zig").GenericMapper;
const common = @import("common.zig");

// TODO: bus conflicts
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
            self.* = Self{
                .prgs = try common.Prgs.init(allocator, info.prg_rom),
                .chrs = try common.Chrs.init(allocator, info.chr_rom),
                .mirroring = info.mirroring,
            };

            self.prgs.setBank(1, self.prgs.bankCount() - 1);
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

        pub fn readPrg(generic: G, addr: u16) ?u8 {
            const self = common.fromGeneric(Self, config, generic);
            if (addr >= 0x8000) {
                return self.prgs.read(addr);
            } else {
                return null;
            }
        }

        pub fn readChr(generic: G, addr: u16) u8 {
            const self = common.fromGeneric(Self, config, generic);
            return self.chrs.read(addr);
        }

        pub fn writePrg(generic: *G, addr: u16, val: u8) void {
            const self = common.fromGeneric(Self, config, generic.*);

            if (addr >= 0x8000 and addr <= 0xffff) {
                self.prgs.setBank(0, @truncate(u4, val));
            }
        }

        pub fn writeChr(generic: *G, addr: u16, val: u8) void {
            const self = common.fromGeneric(Self, config, generic.*);
            self.chrs.write(addr, val);
        }
    };
}
