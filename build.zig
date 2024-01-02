const std = @import("std");

const console = @import("src/console.zig");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const precision = b.option(console.Precision, "precision", "Whether to prioritize performance or accuracy") orelse .accurate;
    const log_step = b.option(bool, "log-step", "Whether to log every cpu step to stdout") orelse false;

    const exe = b.addExecutable(.{
        .name = "badnes",
        .target = target,
        .optimize = optimize,
        .root_source_file = .{ .path = "src/main.zig" },
    });
    exe.linkLibC();
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("opengl");

    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);

    exe_options.addOption(console.Precision, "precision", precision);
    exe_options.addOption(bool, "log_step", log_step);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(.{
        .root_source_file = .{ .path = "src/tests.zig" },
        .target = target,
        .optimize = optimize,
    });
    tests.addOptions("build_options", exe_options);

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run all the tests");
    test_step.dependOn(&run_tests.step);
}
