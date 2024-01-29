// Overengineered mess because I wanted to test metaprogramming
const std = @import("std");
const ascii = std.ascii;

pub const FieldFlagsDef = struct {
    field: []const u8,
    flags: []const u8,
};

pub const FieldFlagsMask = struct {
    field: []const u8,
    mask: u8,
};

pub const FieldFlags = struct {
    /// For disambiguation in case 2 fields share a flag char
    field: ?[]const u8 = null,
    flags: []const u8,
};

/// Helper struct to convert a string of flags to a bit mask
pub fn CreateFlags(comptime T: type, comptime ff_defs: []const FieldFlagsDef) type {
    for (ff_defs) |ff_def| {
        if (std.meta.fieldIndex(T, ff_def.field)) |index| {
            const t = std.meta.fields(T)[index].type;
            if (t != u8) {
                @compileError("Expected field \"" ++ ff_def.field ++ "\" to be a u8, got " ++ t);
            }
        } else {
            @compileError("Field \"" ++ ff_def.field ++ "\" not in struct");
        }

        for (ff_def.flags[0..(ff_def.flags.len - 1)], 0..) |c, i| {
            if (ascii.isDigit(c)) {
                @compileError("Digits not allowed in flags");
            }
            if (c == '?') {
                continue;
            }
            if (std.mem.indexOfScalar(u8, ff_def.flags[(i + 1)..], c) != null) {
                @compileError("Duplicate flag (" ++ [1]u8{c} ++ ") within field \"" ++ ff_def.field ++ "\"");
            }
        }
    }

    return struct {
        const Self = @This();

        /// If FieldFlags.fields == null, attempts to disambiguate using the first letter flag
        /// Psuedocode example: def flag1 = "abcd???g", flag2 = "a?dcefgh"
        /// getFlagMask("234") // ambiguous
        /// getFlagMask("2ab") // ambiguous
        /// getFlagMask("2ba") // flag1
        pub fn getFlagMask(comptime field_flags: FieldFlags) FieldFlagsMask {
            if (field_flags.flags.len == 0) {
                @compileError("0 len flags");
            }

            const ff_def = blk: {
                if (field_flags.field) |field| {
                    // search for requested field
                    for (ff_defs) |f| {
                        if (std.mem.eql(u8, f.field, field)) {
                            break :blk f;
                        }
                    } else {
                        @compileError("Field \"" ++ field ++ "\" doesn't exist");
                    }
                }

                const first_letter: u8 = for (field_flags.flags) |c| {
                    if (c == '?') {
                        @compileError("'?' flag not allowed in get/set");
                    }
                    if (ascii.isAlphabetic(c)) {
                        break c;
                    }
                } else {
                    @compileError("Need at least one letter flag in non-disambiguated get/set");
                };

                // search for any field that contains the first flag
                var result: ?FieldFlagsDef = null;
                for (ff_defs) |f| {
                    if (std.mem.indexOfScalar(u8, f.flags, first_letter) != null) {
                        if (result) |r| {
                            @compileError("Flag '" ++ [1]u8{first_letter} ++
                                "' is ambiguous between fields \"" ++ r.field ++
                                "\" and \"" ++ f.field ++
                                "\"");
                        }
                        result = f;
                    }
                }
                if (result) |r| {
                    break :blk r;
                }
                @compileError("Flag '" ++ [1]u8{first_letter} ++ "' is not in any field");
            };

            var mask = 0;
            for (field_flags.flags) |c| {
                const new_bit = blk: {
                    if (ascii.isDigit(c)) {
                        break :blk 1 << (c - '0');
                    } else if (std.mem.indexOfScalar(u8, ff_def.flags, c)) |i| {
                        break :blk 1 << (7 - i);
                    } else {
                        @compileError("Unknown flag '" ++ [1]u8{c} ++ "'");
                    }
                };
                if (mask & new_bit != 0) {
                    @compileError("Flag '" ++ [1]u8{c} ++ "' accessed via both letter and number indices");
                }
                mask |= new_bit;
            }
            return FieldFlagsMask{
                .field = ff_def.field,
                .mask = mask,
            };
        }

        pub fn getFlag(self: Self, structure: T, comptime field_flags: FieldFlags) bool {
            if (field_flags.flags.len != 1) {
                @compileError("getFlags expect a single flag");
            }
            return self.getFlags(structure, field_flags) != 0;
        }

        pub fn getFlags(_: Self, structure: T, comptime field_flags: FieldFlags) u8 {
            const ff_mask = comptime getFlagMask(field_flags);
            return @field(structure, ff_mask.field) & ff_mask.mask;
        }

        pub fn setFlag(self: Self, structure: *T, comptime field_flags: FieldFlags, val: bool) void {
            if (field_flags.flags.len != 1) {
                @compileError("setFlags expect a single flag");
            }
            self.setFlags(structure, field_flags, if (val) @as(u8, 0xff) else 0x00);
        }

        pub fn setFlags(_: Self, structure: *T, comptime field_flags: FieldFlags, val: u8) void {
            const ff_mask = comptime getFlagMask(field_flags);
            const field = &@field(structure, ff_mask.field);
            setMask(u8, field, val, ff_mask.mask);
        }
    };
}

pub fn getMaskBool(comptime T: type, val: T, mask: T) bool {
    return (val & mask) != 0;
}

pub fn setMask(comptime T: type, lhs: *T, rhs: T, mask: T) void {
    lhs.* = (lhs.* & ~mask) | (rhs & mask);
}

const testing = std.testing;

test "CreateFlags" {
    const TestStruct = struct {
        f1: u8,
        f2: u8,
        f3: u8,
        f4: u8,
    };

    const ff_masks = CreateFlags(TestStruct, ([_]FieldFlagsDef{
        .{ .field = "f1", .flags = "abcdefgh" },
        .{ .field = "f2", .flags = "zyxwvuts" },
        .{ .field = "f3", .flags = "a?c?d?e?" },
        .{ .field = "f4", .flags = "a?c???w?" },
    })[0..]){};

    var test_struct = std.mem.zeroes(TestStruct);

    ff_masks.setFlags(&test_struct, .{ .field = "f1", .flags = "fabcdeg" }, 0xff);

    ff_masks.setFlags(&test_struct, .{ .flags = "zyxwvuts" }, 0xaa);
    ff_masks.setFlag(&test_struct, .{ .flags = "s" }, true);

    ff_masks.setFlags(&test_struct, .{ .field = "f3", .flags = "a6c4" }, 0b1111_0000);
    ff_masks.setFlags(&test_struct, .{ .field = "f3", .flags = "5432e0" }, 0b0000_1101);

    ff_masks.setFlags(&test_struct, .{ .field = "f4", .flags = "w76" }, 0b1110_0010);
    ff_masks.setFlag(&test_struct, .{ .field = "f4", .flags = "7" }, false);
    ff_masks.setFlags(&test_struct, .{ .field = "f4", .flags = "65432w0" }, 0b000_0001);
    ff_masks.setFlag(&test_struct, .{ .field = "f4", .flags = "3" }, true);

    try testing.expectEqual(@as(u8, 0xfe), test_struct.f1);
    try testing.expectEqual(@as(u8, 0xab), test_struct.f2);
    try testing.expectEqual(@as(u8, 0xcd), test_struct.f3);
    try testing.expectEqual(@as(u8, 0x09), test_struct.f4);

    try testing.expect(ff_masks.getFlag(test_struct, .{ .flags = "f" }));
    try testing.expect(!ff_masks.getFlag(test_struct, .{ .flags = "h" }));
    try testing.expect(!ff_masks.getFlag(test_struct, .{ .field = "f4", .flags = "a" }));
    try testing.expect(!ff_masks.getFlag(test_struct, .{ .field = "f4", .flags = "w" }));
    try testing.expectEqual(@as(u8, 0xfe & 0b1110_0001), ff_masks.getFlags(test_struct, .{ .flags = "habc" }));
    try testing.expectEqual(@as(u8, 0b0000_0011), ff_masks.getFlags(test_struct, .{ .flags = "sw2t" }));
}
