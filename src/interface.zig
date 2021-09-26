const std = @import("std");

/// Check that 2 structs both have equivalents of eachother's pub decls (in name only)
/// Mostly because zig won't give me compile errors if I don't manually test both
/// (which I should anyway)
pub fn checkSameInterfaces(comptime interface1: type, comptime interface2: type) void {
    const type_info1 = @typeInfo(interface1).Struct.decls;
    const type_info2 = @typeInfo(interface2).Struct.decls;

    var pubs: comptime_int = 0;
    for (type_info2) |decl| {
        if (decl.is_pub) {
            pubs += 1;
        }
    }

    for (type_info1) |i1_decl| {
        if (!i1_decl.is_pub) {
            continue;
        }

        pubs -= 1;

        for (type_info2) |i2_decl| {
            if (!i2_decl.is_pub) {
                continue;
            }
            if (std.mem.eql(u8, i1_decl.name, i2_decl.name)) {
                break;
            }
        } else {
            @compileError("Interface has no equivalent to " ++ i1_decl.name);
        }
    }

    if (pubs != 0) {
        // not really efficient but it should only get run on error
        checkSameInterfaces(interface2, interface1);
    }
}

pub fn checkAllInterfaces() void {
    const Cpu = @import("cpu.zig").Cpu;
    const Ppu = @import("ppu.zig").Ppu;

    comptime {
        checkSameInterfaces(
            Cpu(.{ .precision = .Fast, .method = .Pure }),
            Cpu(.{ .precision = .Accurate, .method = .Pure }),
        );
    }

    comptime {
        checkSameInterfaces(
            Ppu(.{ .precision = .Fast, .method = .Pure }),
            Ppu(.{ .precision = .Accurate, .method = .Pure }),
        );
    }
}

// Trying to get the pub decls to be the same on precision variants
test "Check interfaces/pub decls" {
    checkAllInterfaces();
}
