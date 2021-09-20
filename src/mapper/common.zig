const Allocator = @import("std").mem.Allocator;
const Mirroring = @import("../ines.zig").Mirroring;

pub const Chr = struct {
    bytes: []u8,
    writeable: bool,

    pub fn init(allocator: *Allocator, bytes: ?[]u8) !Chr {
        if (bytes) |b| {
            return Chr{
                .bytes = b,
                .writeable = false,
            };
        } else {
            return Chr{
                .bytes = try allocator.alloc(u8, 0x2000),
                .writeable = true,
            };
        }
    }

    pub fn deinit(self: Chr, allocator: *Allocator) void {
        allocator.free(self.bytes);
    }

    pub fn read(self: Chr, addr: u16) u8 {
        return self.bytes[addr];
    }

    pub fn write(self: *Chr, addr: u16, val: u8) void {
        if (self.writeable) {
            self.bytes[addr] = val;
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
