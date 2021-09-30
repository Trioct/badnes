const PpuFast = @import("ppu/fast.zig").Ppu;
const PpuAccurate = @import("ppu/accurate.zig").Ppu;

const Config = @import("console.zig").Config;

pub fn Ppu(comptime config: Config) type {
    return switch (config.precision) {
        .fast => PpuFast(config),
        .accurate => PpuAccurate(config),
    };
}
