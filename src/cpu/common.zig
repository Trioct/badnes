const std = @import("std");

const flags_ = @import("../flags.zig");
const StructFlagsMap = flags_.StructFlagsMap;
const FieldFlagsDef = flags_.FieldFlagsDef;

pub fn cpuCycled(self: anytype) void {
    self.apu.runCycle();
    self.ppu.runCycle();
    self.ppu.runCycle();
    self.ppu.runCycle();
    self.mem.cart.cpuCycled();
}

pub const Registers = struct {
    pc: u16,
    s: u8,

    a: u8,
    x: u8,
    y: u8,
    p: u8,

    const Flags = StructFlagsMap(Registers, &.{
        .{ .field = .p, .flags = "NV??DIZC" },
    });

    /// Convenient for testing
    pub fn zeroes() Registers {
        return std.mem.zeroes(Registers);
    }

    /// Real world observed values
    pub fn startup() Registers {
        return Registers{
            .pc = 0x00,
            .s = 0xfd,

            .a = 0x00,
            .x = 0x00,
            .y = 0x00,
            .p = 0x34,
        };
    }

    pub fn getFlag(self: Registers, comptime flags: []const u8) bool {
        return Flags.getFlag(null, flags, self);
    }

    pub fn getFlags(self: Registers, comptime flags: []const u8) u8 {
        return Flags.getFlags(null, flags, self);
    }

    pub fn setFlag(self: *Registers, comptime flags: []const u8, val: bool) void {
        return Flags.setFlag(null, flags, self, val);
    }

    pub fn setFlags(self: *Registers, comptime flags: []const u8, val: u8) void {
        return Flags.setFlags(null, flags, self, val);
    }

    pub fn setFlagsNZ(self: *Registers, val: u8) void {
        self.setFlags("NZ", (val & 0x80) | @as(u8, @intFromBool(val == 0)) << 1);
    }

    fn FieldType(comptime field: []const u8) type {
        std.debug.assert(@hasField(Registers, field) or Registers.hasFlags(field));
        if (std.mem.eql(u8, field, "pc")) {
            return u16;
        } else {
            return u8;
        }
    }

    pub fn get(self: Registers, comptime field: []const u8) FieldType(field) {
        if (@hasField(Registers, field)) {
            return @field(self, field);
        } else if (Registers.hasFlags(field)) {
            return self.getFlags(field);
        } else {
            @compileError("Unknown field for registers");
        }
    }

    pub fn set(self: *Registers, comptime field: []const u8, val: u8) void {
        if (@hasField(Registers, field)) {
            @field(self, field) = val;
        } else if (Registers.hasFlags(field)) {
            return self.setFlags(field, val);
        } else {
            @compileError("Unknown field for registers");
        }
    }
};
