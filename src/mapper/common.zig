const Allocator = @import("std").mem.Allocator;

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
