const std = @import("std");

const console = @import("src/console.zig");

pub fn build(b: *std.build.Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const precision = b.option(console.Precision, "precision", "Whether to prioritize performance or accuracy") orelse .Accurate;
    const log_step = b.option(bool, "log-step", "Whether to log every cpu step to stdout") orelse false;

    const exe = b.addExecutable("badnes", "src/main.zig");
    exe.linkLibC();
    exe.linkSystemLibrary("SDL2");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);

    exe_options.addOption(console.Precision, "precision", precision);
    exe_options.addOption(bool, "log_step", log_step);

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run all the tests");
    test_step.dependOn(b.getInstallStep());

    const tests = b.addTest("src/tests.zig");
    tests.setBuildMode(.Debug);
    tests.addOptions("build_options", exe_options);
    test_step.dependOn(&tests.step);
}
