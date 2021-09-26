const std = @import("std");

const CpuFast = @import("cpu/fast.zig").Cpu;
const CpuAccurate = @import("cpu/accurate.zig").Cpu;

const Config = @import("console.zig").Config;

pub fn Cpu(comptime config: Config) type {
    return switch (config.precision) {
        .Fast => CpuFast(config),
        .Accurate => CpuAccurate(config),
    };
}
