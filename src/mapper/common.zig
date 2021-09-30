const std = @import("std");
const Allocator = std.mem.Allocator;

const Mirroring = @import("../ines.zig").Mirroring;
const Config = @import("../console.zig").Config;
const GenericMapper = @import("../mapper.zig").GenericMapper;

pub const Prgs = BankSwitcher(0x4000, 2);
pub const Chrs = BankSwitcher(0x1000, 2);

pub fn BankSwitcher(comptime size: usize, comptime selectable_banks: usize) type {
    std.debug.assert(std.math.isPowerOfTwo(size));

    const bank_bits = std.math.log2_int(usize, size);
    const BankAddr = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = bank_bits } });

    const full_bits = bank_bits + 1;
    const FullAddr = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = full_bits } });

    return struct {
        const Self = @This();

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
            const offset = blk: while (i <= size) : (i += 1) {
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

pub const Sram = struct {
    bytes: ?[]u8,

    writable: bool = true,
    enabled: bool = true,

    pub fn init(allocator: *Allocator, mapped: bool) !Sram {
        const bytes = blk: {
            if (mapped) {
                const b = try allocator.alloc(u8, 0x2000);
                std.mem.set(u8, b, 0);
                break :blk b;
            } else {
                break :blk null;
            }
        };

        return Sram{
            .bytes = bytes,
        };
    }

    pub fn deinit(self: Sram, allocator: *Allocator) void {
        if (self.bytes) |bytes| {
            allocator.free(bytes);
        }
    }

    pub fn enable(self: *Sram) void {
        self.enabled = true;
    }

    pub fn disable(self: *Sram) void {
        self.enabled = false;
    }

    pub fn read(self: Sram, addr: u16) ?u8 {
        if (self.enabled) {
            if (self.bytes) |bytes| {
                return bytes[addr & 0x1fff];
            }
        }

        return null;
    }

    pub fn write(self: *Sram, addr: u16, val: u8) void {
        if (!(self.enabled and self.writable)) {
            return;
        }

        if (self.bytes) |bytes| {
            bytes[addr & 0x1fff] = val;
        }
    }
};

pub fn mirrorNametable(mirroring: Mirroring, addr: u16) u12 {
    return switch (mirroring) {
        .Horizontal => @truncate(u12, addr & 0xbff),
        .Vertical => @truncate(u12, addr & 0x7ff),
        .FourScreen => @truncate(u12, addr),
    };
}

pub fn fromGeneric(comptime Self: type, comptime config: Config, generic: GenericMapper(config)) *Self {
    return @ptrCast(*Self, generic.mapper_ptr);
}
