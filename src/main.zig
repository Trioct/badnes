const std = @import("std");

const Ines = @import("ines.zig");

const Cpu_ = @import("cpu.zig");
const Cpu = Cpu_.Cpu;

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();

    var allocator = &gpa.allocator;

    var info = try Ines.RomInfo.readFile(allocator, "roms/tests/nestest.nes");
    defer info.deinit(allocator);

    var cpu = Cpu.init();
    defer cpu.deinit(allocator);

    cpu.loadRom(allocator, &info);

    var i: usize = 0;
    while (i < 65536) : (i += 1) {
        cpu.runInstruction(.Fast);
    }
}
