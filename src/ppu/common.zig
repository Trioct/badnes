const flags_ = @import("../flags.zig");
const CreateFlags = flags_.CreateFlags;
const FieldFlagsDef = flags_.FieldFlagsDef;

// https://wiki.nesdev.com/w/index.php?title=PPU_registers
// slightly diverges from nesdev, the last char of flags 0 and 1 are made lowercase
pub fn RegisterMasks(comptime T: type) type {
    return CreateFlags(T, ([_]FieldFlagsDef{
        .{ .field = "ppu_ctrl", .flags = "VPHBSINn" },
        .{ .field = "ppu_mask", .flags = "BGRsbMmg" },
        .{ .field = "ppu_status", .flags = "VSO?????" },
    })[0..]);
}

pub const Address = struct {
    value: u15,

    pub fn coarseX(self: Address) u5 {
        return @truncate(u5, self.value);
    }

    pub fn coarseY(self: Address) u5 {
        return @truncate(u5, self.value >> 5);
    }

    pub fn nametableSelect(self: Address) u2 {
        return @truncate(u2, self.value >> 10);
    }

    pub fn fineY(self: Address) u3 {
        return @truncate(u3, self.value >> 12);
    }

    pub fn fullY(self: Address) u8 {
        return (@as(u8, self.coarseY()) << 3) | self.fineY();
    }
};

pub const palette = [_]u32{
    0x00666666,
    0x00002a88,
    0x001412a7,
    0x003b00a4,
    0x005c007e,
    0x006e0040,
    0x006c0600,
    0x00561d00,
    0x00333500,
    0x000b4800,
    0x00005200,
    0x00004f08,
    0x0000404d,
    0x00000000,
    0x00000000,
    0x00000000,
    0x00adadad,
    0x00155fd9,
    0x004240ff,
    0x007527fe,
    0x00a01acc,
    0x00b71e7b,
    0x00b53120,
    0x00994e00,
    0x006b6d00,
    0x00388700,
    0x000c9300,
    0x00008f32,
    0x00007c8d,
    0x00000000,
    0x00000000,
    0x00000000,
    0x00fffeff,
    0x0064b0ff,
    0x009290ff,
    0x00c676ff,
    0x00f36aff,
    0x00fe6ecc,
    0x00fe8170,
    0x00ea9e22,
    0x00bcbe00,
    0x0088d800,
    0x005ce430,
    0x0045e082,
    0x0048cdde,
    0x004f4f4f,
    0x00000000,
    0x00000000,
    0x00fffeff,
    0x00c0dfff,
    0x00d3d2ff,
    0x00e8c8ff,
    0x00fbc2ff,
    0x00fec4ea,
    0x00feccc5,
    0x00f7d8a5,
    0x00e4e594,
    0x00cfef96,
    0x00bdf4ab,
    0x00b3f3cc,
    0x00b5ebf2,
    0x00b8b8b8,
    0x00000000,
    0x00000000,
};
