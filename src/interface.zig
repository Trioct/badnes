const std = @import("std");

/// Check that 2 structs both have equivalents of eachother's pub decls (in name only)
/// Mostly because zig won't give me compile errors if I don't manually test both
/// (which I should anyway)
pub fn checkSameInterfaces(comptime interface1: type, comptime interface2: type) void {
    const type_info1 = @typeInfo(interface1).Struct.decls;
    const type_info2 = @typeInfo(interface2).Struct.decls;

    for (type_info1) |i1_decl| {
        for (type_info2) |i2_decl| {
            if (std.mem.eql(u8, i1_decl.name, i2_decl.name)) {
                break;
            }
        } else {
            @compileError("Interface has no equivalent to " ++ i1_decl.name);
        }
    }
}

pub fn checkAllInterfaces() void {
    const Cpu = @import("cpu.zig").Cpu;
    const Ppu = @import("ppu.zig").Ppu;

    comptime {
        checkSameInterfaces(
            Cpu(.{ .precision = .fast, .method = .pure }),
            Cpu(.{ .precision = .accurate, .method = .pure }),
        );
    }

    comptime {
        checkSameInterfaces(
            Ppu(.{ .precision = .fast, .method = .pure }),
            Ppu(.{ .precision = .accurate, .method = .pure }),
        );
    }
}

// Trying to get the pub decls to be the same on precision variants
test "Check interfaces/pub decls" {
    checkAllInterfaces();
}
