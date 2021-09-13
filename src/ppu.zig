const PpuFast = @import("fast/ppu.zig").Ppu;
const PpuAccurate = @import("accurate/ppu.zig").Ppu;

const Precision = @import("main.zig").Precision;

pub fn Ppu(comptime precision: Precision) type {
    return switch (precision) {
        .Fast => PpuFast,
        .Accurate => PpuAccurate,
    };
}
