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

    const imgui = b.option(bool, "imgui", "Use imgui for extra features") orelse false;

    const precision = b.option(console.Precision, "precision", "Whether to prioritize performance or accuracy") orelse .accurate;
    const log_step = b.option(bool, "log-step", "Whether to log every cpu step to stdout") orelse false;

    const exe = b.addExecutable("badnes", "src/main.zig");
    exe.linkLibC();
    exe.linkSystemLibrary("SDL2");
    exe.linkSystemLibrary("opengl");

    if (imgui) {
        linkImgui(b, exe);
    }

    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.install();

    const exe_options = b.addOptions();
    exe.addOptions("build_options", exe_options);

    exe_options.addOption(console.Precision, "precision", precision);
    exe_options.addOption(bool, "log_step", log_step);
    exe_options.addOption(bool, "imgui", imgui);

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

fn linkImgui(b: *std.build.Builder, exe: *std.build.LibExeObjStep) void {
    const imgui = b.addStaticLibrary("imgui", null);
    imgui.linkLibC();
    imgui.linkLibCpp();
    imgui.linkSystemLibrary("SDL2");
    imgui.linkSystemLibrary("opengl");
    imgui.addIncludeDir("cimgui/imgui");

    imgui.defineCMacro("IMGUI_DISABLE_OBSOLETE_FUNCTIONS", "1");
    imgui.defineCMacro("IMGUI_IMPL_API", "extern \"C\"");
    const source_files = [_]([]const u8){
        "cimgui/imgui/imgui.cpp",
        "cimgui/imgui/imgui_tables.cpp",
        "cimgui/imgui/imgui_draw.cpp",
        "cimgui/imgui/imgui_widgets.cpp",
        "cimgui/imgui/imgui_demo.cpp",
        "cimgui/imgui/backends/imgui_impl_opengl3.cpp",
        "cimgui/imgui/backends/imgui_impl_sdl.cpp",
        "cimgui/cimgui.cpp",
    };

    var flags = std.ArrayList([]const u8).init(std.heap.page_allocator);
    if (b.is_release) flags.append("-Os") catch unreachable;

    imgui.addCSourceFiles(source_files[0..], flags.items[0..]);

    exe.addIncludeDir("cimgui");
    exe.addIncludeDir("cimgui/generator/output");
    exe.linkLibrary(imgui);
}
