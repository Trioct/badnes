// Overengineered mess because I wanted to test metaprogramming
const std = @import("std");
const ascii = std.ascii;
const meta = std.meta;

pub const DefaultFlagMap = FlagMap("????????");

pub fn FlagMap(comptime str: []const u8) type {
    if (str.len != 8) {
        @compileError("Flag definition must use 8 characters for 8 bits");
    }

    for (str, 0..) |c, i| {
        if (ascii.isDigit(c)) {
            @compileError("Digits not allowed in flags");
        }
        if (c == '?') {
            continue;
        }
        if (std.mem.indexOfScalar(u8, str[i + 1 ..], c) != null) {
            @compileError("Duplicate flag '" ++ [1]u8{c} ++ "'");
        }
    }

    return struct {
        pub fn getMask(comptime flags: []const u8) u8 {
            var mask = 0;
            for (flags) |c| {
                const new_bit = blk: {
                    if (ascii.isDigit(c)) {
                        break :blk 1 << (c - '0');
                    } else if (std.mem.indexOfScalar(u8, str, c)) |i| {
                        break :blk 1 << (7 - i);
                    } else {
                        @compileError("Unknown flag '" ++ [1]u8{c} ++ "'");
                    }
                };
                if (mask & new_bit != 0) {
                    @compileError("Flag '" ++ [1]u8{c} ++
                        "' accessed via both letter and number indices");
                }
                mask |= new_bit;
            }
            return mask;
        }

        pub fn getFlag(comptime flags: []const u8, src: u8) bool {
            if (flags.len != 1) {
                @compileError("getFlags expects a single flag");
            }
            return getFlags(flags, src) != 0;
        }

        pub fn getFlags(comptime flags: []const u8, src: u8) u8 {
            const mask = comptime getMask(flags);
            return src & mask;
        }

        pub fn setFlag(comptime flags: []const u8, src: *u8, val: bool) void {
            if (flags.len != 1) {
                @compileError("setFlags expects a single flag");
            }
            setFlags(flags, src, if (val) @as(u8, 0xff) else 0x00);
        }

        pub fn setFlags(comptime flags: []const u8, src: *u8, val: u8) void {
            const mask = comptime getMask(flags);
            setMask(u8, src, val, mask);
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

pub fn FieldFlags(comptime T: type) type {
    return struct {
        /// For disambiguation in case 2 fields share a flag char
        field: ?meta.FieldEnum(T) = null,
        flags: []const u8,
    };
}

pub fn CreateFlags(comptime T: type, comptime ff_defs: []const FieldFlagsDef(T)) type {
    const FieldEnum = meta.FieldEnum(T);
    const fields = meta.fields(T);

    for (ff_defs, 0..) |ff_def, i| {
        const t = fields[@intFromEnum(ff_def.field)].type;
        if (t != u8) {
            @compileError("Expected field \"" ++ ff_def.field ++ "\" to be a u8, got " ++ t);
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
        pub const FF = FieldFlags(T);

        /// If FieldFlags.fields == null, attempts to disambiguate using the first letter flag
        /// Psuedocode example: def flag1 = "abcd???g", flag2 = "a?dcefgh"
        /// getFlagMask("234") // ambiguous
        /// getFlagMask("2ab") // ambiguous
        /// getFlagMask("2ba") // flag1
        pub fn getFlagsDef(comptime field_flags: FF) FFDef {
            if (ff_defs.len == 1) {
                return ff_defs[0];
            }

            if (field_flags.field) |field| {
                for (ff_defs) |def| {
                    if (def.field == field) {
                        return def;
                    }
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
            var result: ?FFDef = null;
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
                return r;
            }
            @compileError("Flag '" ++ [1]u8{first_letter} ++ "' is not in any field");
        }

        pub fn getFieldFlagsMap(comptime field_flags: FF) FFMap {
            const ff_def = comptime getFlagsDef(field_flags);
            return FFMap{
                .field = ff_def.field,
                .map = FlagMap(ff_def.flags),
            };
        }

        pub fn getFlag(structure: T, comptime field_flags: FF) bool {
            const ff_map = getFieldFlagsMap(field_flags);
            return ff_map.map.getFlag(
                field_flags.flags,
                getFieldFromEnum(ff_map.field, structure),
            );
        }

        pub fn getFlags(structure: T, comptime field_flags: FF) u8 {
            const ff_map = getFieldFlagsMap(field_flags);
            return ff_map.map.getFlags(
                field_flags.flags,
                getFieldFromEnum(ff_map.field, structure),
            );
        }

        pub fn setFlag(structure: *T, comptime field_flags: FF, val: bool) void {
            const ff_map = getFieldFlagsMap(field_flags);
            ff_map.map.setFlag(
                field_flags.flags,
                getFieldFromEnumMut(ff_map.field, structure),
                val,
            );
        }

        pub fn setFlags(structure: *T, comptime field_flags: FF, val: u8) void {
            const ff_map = getFieldFlagsMap(field_flags);
            ff_map.map.setFlags(
                field_flags.flags,
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

test "CreateFlags" {
    const TestStruct = struct {
        f1: u8,
        f2: u8,
        f3: u8,
        f4: u8,
    };

    const Flags = CreateFlags(TestStruct, &.{
        .{ .field = .f1, .flags = "abcdefgh" },
        .{ .field = .f2, .flags = "zyxwvuts" },
        .{ .field = .f3, .flags = "a?c?d?e?" },
        .{ .field = .f4, .flags = "a?c???w?" },
    });

    var test_struct = std.mem.zeroes(TestStruct);

    Flags.setFlags(&test_struct, .{ .field = .f1, .flags = "fabcdeg" }, 0xff);

    Flags.setFlags(&test_struct, .{ .flags = "zyxwvuts" }, 0xaa);
    Flags.setFlag(&test_struct, .{ .flags = "s" }, true);

    Flags.setFlags(&test_struct, .{ .field = .f3, .flags = "a6c4" }, 0b1111_0000);
    Flags.setFlags(&test_struct, .{ .field = .f3, .flags = "5432e0" }, 0b0000_1101);

    Flags.setFlags(&test_struct, .{ .field = .f4, .flags = "w76" }, 0b1110_0010);
    Flags.setFlag(&test_struct, .{ .field = .f4, .flags = "7" }, false);
    Flags.setFlags(&test_struct, .{ .field = .f4, .flags = "65432w0" }, 0b000_0001);
    Flags.setFlag(&test_struct, .{ .field = .f4, .flags = "3" }, true);

    try testing.expectEqual(@as(u8, 0xfe), test_struct.f1);
    try testing.expectEqual(@as(u8, 0xab), test_struct.f2);
    try testing.expectEqual(@as(u8, 0xcd), test_struct.f3);
    try testing.expectEqual(@as(u8, 0x09), test_struct.f4);

    try testing.expect(Flags.getFlag(test_struct, .{ .flags = "f" }));
    try testing.expect(!Flags.getFlag(test_struct, .{ .flags = "h" }));
    try testing.expect(!Flags.getFlag(test_struct, .{ .field = .f4, .flags = "a" }));
    try testing.expect(!Flags.getFlag(test_struct, .{ .field = .f4, .flags = "w" }));
    try testing.expectEqual(@as(u8, 0xfe & 0b1110_0001), Flags.getFlags(test_struct, .{ .flags = "habc" }));
    try testing.expectEqual(@as(u8, 0b0000_0011), Flags.getFlags(test_struct, .{ .flags = "sw2t" }));
}
