const std = @import("std");
const Allocator = std.mem.Allocator;

const Mirroring = @import("../ines.zig").Mirroring;
const Config = @import("../console.zig").Config;
const GenericMapper = @import("../mapper.zig").GenericMapper;

pub const Prgs = BankSwitcher(0x4000);
pub const Chrs = BankSwitcher(0x1000);

pub fn BankSwitcher(comptime size: usize) type {
    std.debug.assert(std.math.isPowerOfTwo(size));

    const bank_bits = std.math.log2_int(usize, size);
    const BankAddr = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = bank_bits } });

    const full_bits = bank_bits + 1;
    const FullAddr = @Type(.{ .Int = .{ .signedness = .unsigned, .bits = full_bits } });

    return struct {
        const Self = @This();

        bytes: []u8,
        writeable: bool,

        selected: [2]usize,

        pub fn init(allocator: *Allocator, bytes: ?[]u8) !Self {
            if (bytes) |b| {
                const second_selected = if (b.len == size) 0 else size;
                return Self{
                    .bytes = b,
                    .writeable = false,
                    .selected = [2]usize{ 0, second_selected },
                };
            } else {
                const b = try allocator.alloc(u8, size * 2);
                std.mem.set(u8, b, 0);
                return Self{
                    .bytes = b,
                    .writeable = true,
                    .selected = [2]usize{ 0, size },
                };
            }
        }

        pub fn deinit(self: Self, allocator: *Allocator) void {
            allocator.free(self.bytes);
        }

        pub fn lastBankIndex(self: Self) usize {
            return @divExact(self.bytes.len, size) - 1;
        }

        pub fn setBank(self: *Self, selected: u1, bank: usize) void {
            self.selected[selected] = bank * size;
        }

        pub fn setBothBanks(self: *Self, bank: usize) void {
            self.setBank(0, bank);
            self.setBank(1, bank + 1);
        }

        pub fn mapAddr(self: Self, addr: FullAddr) usize {
            const offset = switch (addr) {
                0x0000...(size - 1) => self.selected[0],
                size...(size * 2 - 1) => self.selected[1],
            };
            return offset | @truncate(BankAddr, addr);
        }

        pub fn read(self: Self, addr: u16) u8 {
            return self.bytes[self.mapAddr(@truncate(FullAddr, addr))];
        }

        pub fn write(self: *Self, addr: u16, val: u8) void {
            if (self.writeable) {
                self.bytes[self.mapAddr(@truncate(FullAddr, addr))] = val;
            }
        }
    };
}

pub const Sram = struct {
    bytes: ?[]u8,

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

    pub fn read(self: Sram, addr: u16) u8 {
        if (self.bytes) |bytes| {
            return bytes[addr & 0x1fff];
        } else {
            return 0;
        }
    }

    pub fn write(self: *Sram, addr: u16, val: u8) void {
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
