// Overengineered mess because I wanted to test metaprogramming
const std = @import("std");
const ascii = std.ascii;
const meta = std.meta;

pub const DefaultFlagMap = FlagMap("????????");

pub fn FlagMap(comptime str: []const u8) type {
    for (str) |c| {
        if (ascii.isDigit(c)) {
            @compileError("Digits not allowed in flags");
        }
    }

    return struct {
        pub const bits = str.len;
        pub const T = meta.Int(.unsigned, bits);

        pub fn getMask(comptime flags: []const u8) T {
            comptime var mask = 0;
            comptime var i: usize = 0;
            inline for (flags) |c| {
                const new_bit = blk: {
                    comptime if (ascii.isDigit(c)) {
                        break :blk 1 << (c - '0');
                    } else if (std.mem.indexOfScalarPos(u8, str, i, c)) |pos| {
                        i = pos + 1;
                        break :blk 1 << (bits - 1 - pos);
                    } else {
                        @compileError("Unknown flag '" ++ [1]u8{c} ++ "'");
                    };
                };
                if (mask & new_bit != 0) {
                    @compileError("Flag '" ++ [1]u8{c} ++
                        "' accessed via both letter and number indices");
                }
                mask |= new_bit;
            }
            return mask;
        }

        pub fn getFlag(comptime flags: []const T, src: T) bool {
            if (flags.len != 1) {
                @compileError("getFlags expects a single flag");
            }
            return getFlags(flags, src) != 0;
        }

        pub fn getFlags(comptime flags: []const u8, src: T) T {
            const mask = comptime getMask(flags);
            return src & mask;
        }

        /// Get flags but shift the result as far right as possible
        pub fn getFlagsShifted(comptime flags: []const u8, src: T) T {
            const mask = comptime getMask(flags);
            const shift = @ctz(mask);
            return (src & mask) >> shift;
        }

        pub fn setFlag(comptime flags: []const u8, src: *T, val: bool) void {
            if (flags.len != 1) {
                @compileError("setFlags expects a single flag");
            }
            setFlags(flags, src, if (val) @as(u8, 0xff) else 0x00);
        }

        pub fn setFlags(comptime flags: []const u8, src: *T, val: T) void {
            const mask = comptime getMask(flags);
            setMask(T, src, val, mask);
        }
    };
}

pub fn FieldFlagsDef(comptime T: type) type {
    return struct {
        field: meta.FieldEnum(T),
        flags: []const u8,
    };
}

pub fn FieldFlagsMap(comptime T: type) type {
    return struct {
        field: meta.FieldEnum(T),
        map: type,
    };
}

pub fn StructFlagsMap(comptime T: type, comptime ff_defs: []const FieldFlagsDef(T)) type {
    const fields = meta.fields(T);

    for (ff_defs, 0..) |ff_def, i| {
        const field = fields[@intFromEnum(ff_def.field)];
        const ExpectedType = meta.Int(.unsigned, ff_def.flags.len);
        if (field.type != ExpectedType) {
            @compileError("Expected field \"" ++ field.name ++ "\" to be a " ++
                @typeName(ExpectedType) ++ ", got " ++ @typeName(field.type));
        }

        for (ff_defs[i + 1 ..]) |ff_def2| {
            if (ff_def.field == ff_def2.field) {
                @compileError("Field has multiple flag definitions");
            }
        }
    }

    return struct {
        pub const FFDef = FieldFlagsDef(T);
        pub const FFMap = FieldFlagsMap(T);
        pub const FieldEnum = meta.FieldEnum(T);

        /// If FieldFlags.fields == null, attempts to disambiguate
        /// Psuedocode example: def flag1 = "abcd???g", flag2 = "a?dcefgh"
        /// getFlagsDef("2a4") // ambiguous
        /// getFlagsDef("2ab") // flag1
        pub fn getFlagsDef(comptime field: ?FieldEnum, comptime flags: []const u8) FFDef {
            if (ff_defs.len == 1) {
                return ff_defs[0];
            }

            if (field) |f| {
                for (ff_defs) |def| {
                    if (def.field == f) {
                        return def;
                    }
                }
            }

            var result: ?FFDef = null;
            outer: for (ff_defs) |f| {
                for (flags) |flag| {
                    if (ascii.isDigit(flag)) {
                        continue;
                    }
                    if (std.mem.indexOfScalar(u8, f.flags, flag) == null) {
                        continue :outer;
                    }
                }

                if (result) |r| {
                    @compileError("Flags \"" ++ flags ++
                        "\" is ambiguous between fields \"" ++ r.field ++
                        "\" and \"" ++ f.field ++
                        "\"");
                }
                result = f;
            }

            if (result) |r| {
                return r;
            }

            @compileError("Flags \"" ++ flags ++ "\" do not fit any field");
        }

        pub fn getFieldFlagsMap(comptime field: ?FieldEnum, comptime flags: []const u8) FFMap {
            const ff_def = comptime getFlagsDef(field, flags);
            return FFMap{
                .field = ff_def.field,
                .map = FlagMap(ff_def.flags),
            };
        }

        pub fn getFlag(
            comptime field: ?FieldEnum,
            comptime flags: []const u8,
            structure: T,
        ) bool {
            const ff_map = getFieldFlagsMap(field, flags);
            return ff_map.map.getFlag(
                flags,
                getFieldFromEnum(ff_map.field, structure),
            );
        }

        pub fn getFlags(
            comptime field: ?FieldEnum,
            comptime flags: []const u8,
            structure: T,
        ) getFieldFlagsMap(field, flags).map.T {
            const ff_map = getFieldFlagsMap(field, flags);
            return ff_map.map.getFlags(
                flags,
                getFieldFromEnum(ff_map.field, structure),
            );
        }

        /// Get flags but shift the result as far right as possible
        pub fn getFlagsShifted(
            comptime field: ?FieldEnum,
            comptime flags: []const u8,
            structure: T,
        ) getFieldFlagsMap(field, flags).map.T {
            const ff_map = getFieldFlagsMap(field, flags);
            return ff_map.map.getFlagsShifted(
                flags,
                getFieldFromEnum(ff_map.field, structure),
            );
        }

        pub fn setFlag(
            comptime field: ?FieldEnum,
            comptime flags: []const u8,
            structure: *T,
            val: bool,
        ) void {
            const ff_map = getFieldFlagsMap(field, flags);
            ff_map.map.setFlag(
                flags,
                getFieldFromEnumMut(ff_map.field, structure),
                val,
            );
        }

        pub fn setFlags(
            comptime field: ?FieldEnum,
            comptime flags: []const u8,
            structure: *T,
            val: getFieldFlagsMap(field, flags).map.T,
        ) void {
            const ff_map = getFieldFlagsMap(field, flags);
            ff_map.map.setFlags(
                flags,
                getFieldFromEnumMut(ff_map.field, structure),
                val,
            );
        }

        fn getFieldFromEnum(
            comptime field: FieldEnum,
            structure: T,
        ) fields[@intFromEnum(field)].type {
            return @field(structure, fields[@intFromEnum(field)].name);
        }

        fn getFieldFromEnumMut(
            comptime field: FieldEnum,
            structure: *T,
        ) *fields[@intFromEnum(field)].type {
            return &@field(structure, fields[@intFromEnum(field)].name);
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

test "StructFlagsMap" {
    const TestStruct = struct {
        f1: u8,
        f2: u8,
        f3: u8,
        f4: u8,
        f5: u6,
    };

    const Flags = StructFlagsMap(TestStruct, &.{
        .{ .field = .f1, .flags = "abcdefgh" },
        .{ .field = .f2, .flags = "zyxwvuts" },
        .{ .field = .f3, .flags = "a?c?d?e?" },
        .{ .field = .f4, .flags = "a?c???w?" },
        .{ .field = .f5, .flags = "xxxxyy" },
    });

    var test_struct = std.mem.zeroes(TestStruct);

    Flags.setFlags(.f1, "abcdefg", &test_struct, 0xff);

    Flags.setFlags(null, "zyxwvuts", &test_struct, 0xaa);
    Flags.setFlag(null, "s", &test_struct, true);

    Flags.setFlags(.f3, "a6c4", &test_struct, 0b1111_0000);
    Flags.setFlags(.f3, "5432e0", &test_struct, 0b0000_1101);

    Flags.setFlags(.f4, "w76", &test_struct, 0b1110_0010);
    Flags.setFlag(.f4, "7", &test_struct, false);
    Flags.setFlags(.f4, "65432w0", &test_struct, 0b000_0001);
    Flags.setFlag(.f4, "3", &test_struct, true);
    Flags.setFlags(.f5, "xxxx", &test_struct, 0b01_1000);
    Flags.setFlags(.f5, "yy", &test_struct, 0b00_0011);

    try testing.expectEqual(@as(u8, 0xfe), test_struct.f1);
    try testing.expectEqual(@as(u8, 0xab), test_struct.f2);
    try testing.expectEqual(@as(u8, 0xcd), test_struct.f3);
    try testing.expectEqual(@as(u8, 0x09), test_struct.f4);
    try testing.expectEqual(@as(u6, 0x1b), test_struct.f5);

    try testing.expect(Flags.getFlag(null, "f", test_struct));
    try testing.expect(!Flags.getFlag(null, "h", test_struct));
    try testing.expect(!Flags.getFlag(.f4, "a", test_struct));
    try testing.expect(!Flags.getFlag(.f4, "w", test_struct));
    try testing.expectEqual(@as(u8, 0xfe & 0b1110_0001), Flags.getFlags(null, "abch", test_struct));
    try testing.expectEqual(@as(u8, 0b0000_0011), Flags.getFlags(null, "wts2", test_struct));
    try testing.expectEqual(@as(u6, 0b11_1100), Flags.getFieldFlagsMap(.f5, "xxxx").map.getMask("xxxx"));
    try testing.expectEqual(@as(u6, 0b01_1000), Flags.getFlags(.f5, "xxxx", test_struct));
    try testing.expectEqual(@as(u6, 0b00_0110), Flags.getFlagsShifted(.f5, "xxxx", test_struct));
    try testing.expectEqual(@as(u6, 0b00_0011), Flags.getFlags(.f5, "yy", test_struct));
    try testing.expectEqual(@as(u6, 0b00_0011), Flags.getFlagsShifted(.f5, "yy", test_struct));
}
