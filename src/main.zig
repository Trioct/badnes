const std = @import("std");
const Allocator = std.mem.Allocator;

const build_options = @import("build_options");

const console_ = @import("console.zig");
const Console = console_.Console;
const Precision = console_.Precision;
const IoMethod = console_.IoMethod;

const sdl_bindings = @import("sdl/bindings.zig");
const Sdl = sdl_bindings.Sdl;
const video = @import("video.zig");
const audio = @import("audio.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();

    var allocator = &gpa.allocator;

    var args_iter = std.process.args();
    _ = args_iter.skip();

    const rom_path = blk: {
        if (args_iter.next(allocator)) |arg| {
            break :blk try arg;
        } else {
            break :blk try allocator.dupe(u8, "roms/tests/nestest.nes");
        }
    };
    defer allocator.free(rom_path);

    try Sdl.init(.{sdl_bindings.c.SDL_INIT_VIDEO | sdl_bindings.c.SDL_INIT_AUDIO | sdl_bindings.c.SDL_INIT_EVENTS});
    defer Sdl.quit();

    var console = Console(.{
        .precision = comptime std.meta.stringToEnum(Precision, @tagName(build_options.precision)).?,
        .method = .sdl,
    }).alloc();

    const sdl_context = if (build_options.imgui) .sdl_imgui else .sdl_basic;
    var video_context = try video.Context(sdl_context).init(allocator, &console, "Badnes");
    defer video_context.deinit(allocator);

    var audio_context = try audio.Context(.sdl).alloc(allocator);
    // TODO: need a errdefer too but lazy
    try audio_context.init();
    defer audio_context.deinit(allocator);

    console.init(allocator, video_context.getGamePixelBuffer(), &audio_context);
    defer console.deinit();

    try console.loadRom(rom_path);

    var event: sdl_bindings.c.SDL_Event = undefined;

    var total_time: i128 = 0;
    var frames: usize = 0;
    mloop: while (true) {
        while (Sdl.pollEvent(.{&event}) == 1) {
            if (!video_context.handleEvent(event)) {
                break :mloop;
            }
        }
        if (console.ppu.present_frame) {
            frames += 1;
            console.ppu.present_frame = false;
            total_time += try video_context.draw(.{ .timing = .timed });

            if (total_time > std.time.ns_per_s) {
                //std.debug.print("FPS: {}\n", .{frames});
                frames = 0;
                total_time -= std.time.ns_per_s;
            }
            if (frames > 4) {
                audio_context.unpause();
            }
        }

        // Batch run instructions/cycles to not get bogged down by Sdl.pollEvent
        var i: usize = 0;
        switch (build_options.precision) {
            .fast => {
                while (i < 2000) : (i += 1) {
                    console.cpu.runStep();
                }
            },
            .accurate => {
                while (i < 5000) : (i += 1) {
                    console.cpu.runStep();
                }
            },
        }
    }
}
