const std = @import("std");
const Allocator = std.mem.Allocator;

const Mirroring = @import("../ines.zig").Mirroring;
const Config = @import("../console.zig").Config;
const GenericMapper = @import("../mapper.zig").GenericMapper;
const MapperState = @import("../mapper.zig").MapperState;

pub const Prgs = BankSwitcher(0x4000, 2);
pub const Chrs = BankSwitcher(0x1000, 2);

pub fn BankSwitcher(comptime size: usize, comptime selectable_banks: usize) type {
    std.debug.assert(std.math.isPowerOfTwo(size));

    const bank_bits = std.math.log2_int(usize, size);
    const BankAddr = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = bank_bits } });

    const full_bits = bank_bits + std.math.log2_int(usize, selectable_banks);
    const FullAddr = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = full_bits } });

    return struct {
        const Self = @This();
        const size: usize = size;
        const selectable_banks: usize = selectable_banks;

        bytes: []u8,
        writable: bool,

        selected: [selectable_banks]usize,

        pub fn init(allocator: *Allocator, bytes: ?[]u8) !Self {
            var bank_switcher = blk: {
                if (bytes) |b| {
                    break :blk Self{
                        .bytes = b,
                        .writable = false,
                        .selected = [_]usize{undefined} ** selectable_banks,
                    };
                } else {
                    const b = try allocator.alloc(u8, size * selectable_banks);
                    std.mem.set(u8, b, 0);
                    break :blk Self{
                        .bytes = b,
                        .writable = true,
                        .selected = [_]usize{undefined} ** selectable_banks,
                    };
                }
            };

            for (bank_switcher.selected) |*b, i| {
                b.* = (i % (bank_switcher.bankCount())) * size;
            }

            return bank_switcher;
        }

        pub fn deinit(self: Self, allocator: *Allocator) void {
            allocator.free(self.bytes);
        }

        pub fn bankCount(self: Self) usize {
            return @divExact(self.bytes.len, size);
        }

        pub fn getSelectedBankIndex(self: Self, selected_index: usize) usize {
            return @divExact(self.selected[selected_index], size);
        }

        pub fn setBank(self: *Self, selected: usize, bank: usize) void {
            self.selected[selected] = bank * size;
        }

        pub fn setConsecutiveBanks(self: *Self, selected: usize, count: usize, bank: usize) void {
            std.debug.assert(bank + count <= self.bankCount());
            std.debug.assert(selected + count <= self.selected.len);

            var i: usize = 0;
            while (i < count) : (i += 1) {
                self.setBank(selected + i, bank + i);
            }
        }

        pub fn mapAddr(self: Self, addr: FullAddr) usize {
            var i: usize = 0;
            const offset = blk: while (i < selectable_banks) : (i += 1) {
                if (addr >= i * size and addr < (i + 1) * size) {
                    break :blk self.selected[i];
                }
            } else unreachable;
            return offset | @truncate(BankAddr, addr);
        }

        pub fn read(self: Self, addr: u16) u8 {
            return self.bytes[self.mapAddr(@truncate(FullAddr, addr))];
        }

        pub fn write(self: *Self, addr: u16, val: u8) void {
            if (self.writable) {
                self.bytes[self.mapAddr(@truncate(FullAddr, addr))] = val;
            }
        }
    };
}

pub const PrgRam = struct {
    bytes: ?[]u8,

    writable: bool = true,
    enabled: bool = true,
    // TODO: used for savegames, etc.
    persistent: bool = false,

    pub fn init(allocator: *Allocator, mapped: bool, persistent: bool) !PrgRam {
        const bytes = blk: {
            if (mapped) {
                const b = try allocator.alloc(u8, 0x2000);
                std.mem.set(u8, b, 0);
                break :blk b;
            } else {
                break :blk null;
            }
        };

        return PrgRam{
            .bytes = bytes,
            .persistent = persistent,
        };
    }

    pub fn deinit(self: PrgRam, allocator: *Allocator) void {
        if (self.bytes) |bytes| {
            allocator.free(bytes);
        }
    }

    pub fn enable(self: *PrgRam) void {
        self.enabled = true;
    }

    pub fn disable(self: *PrgRam) void {
        self.enabled = false;
    }

    pub fn read(self: PrgRam, addr: u16) ?u8 {
        if (self.enabled) {
            if (self.bytes) |bytes| {
                return bytes[addr & 0x1fff];
            }
        }

        return null;
    }

    pub fn write(self: *PrgRam, addr: u16, val: u8) void {
        if (!(self.enabled and self.writable)) {
            return;
        }

        if (self.bytes) |bytes| {
            bytes[addr & 0x1fff] = val;
        }
    }
};

pub fn fromGeneric(comptime Self: type, comptime config: Config, generic: GenericMapper(config)) *Self {
    return @ptrCast(*Self, generic.mapper_ptr);
}

// TODO: redo when they make this api better
pub fn getState(
    comptime Self: type,
    comptime config: Config,
    comptime prg_bank_switcher: []const u8,
) fn (GenericMapper(config)) MapperState {
    return (struct {
        fn f(generic: GenericMapper(config)) MapperState {
            const self = fromGeneric(Self, config, generic);
            const prgs = &@field(self, prg_bank_switcher);
            return MapperState{
                .prg_rom_bank_size = @TypeOf(prgs.*).size,
                .prg_rom_selected_banks = &prgs.selected,
            };
        }
    }).f;
}

pub fn mirrorNametable(mirroring: Mirroring, addr: u16) u12 {
    return switch (mirroring) {
        .horizontal => @truncate(u12, addr & 0xbff),
        .vertical => @truncate(u12, addr & 0x7ff),
        .four_screen => @truncate(u12, addr),
    };
}
