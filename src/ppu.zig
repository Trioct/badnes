const PpuFast = @import("ppu/fast.zig").Ppu;
const PpuAccurate = @import("ppu/accurate.zig").Ppu;

const Precision = @import("console.zig").Precision;

pub fn Ppu(comptime precision: Precision) type {
    return switch (precision) {
        .Fast => PpuFast,
        .Accurate => PpuAccurate,
    };
}
