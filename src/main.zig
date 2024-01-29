const std = @import("std");
const Allocator = std.mem.Allocator;

const build_options = @import("build_options");

const console_ = @import("console.zig");
const Console = console_.Console;
const Precision = console_.Precision;
const IoMethod = console_.IoMethod;

const Sdl = @import("sdl/bindings.zig").Sdl;
const video = @import("video.zig");
const audio = @import("audio.zig");

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();

    const allocator = gpa.allocator();

    try Sdl.init(Sdl.init_video | Sdl.init_audio | Sdl.init_events);
    defer Sdl.quit();

    var console = Console(.{
        .precision = comptime std.meta.stringToEnum(Precision, @tagName(build_options.precision)).?,
        .method = .sdl,
    }).alloc();

    var video_context = try video.Context(.sdl_basic).init(allocator, "Badnes");
    defer video_context.deinit(allocator);

    var audio_context = try audio.Context(.sdl).alloc(allocator);
    audio_context.init() catch |err| {
        audio_context.free(allocator);
        return err;
    };
    defer audio_context.deinit(allocator);

    console.init(allocator, video_context.getGamePixelBuffer(), &audio_context);
    defer console.deinit();

    var args_iter = try std.process.argsWithAllocator(allocator);
    defer args_iter.deinit();
    _ = args_iter.skip();

    if (args_iter.next()) |arg| {
        try console.loadRom(arg);
    }

    var event: Sdl.Event = undefined;

    var total_time: i128 = 0;
    var frames: usize = 0;
    mloop: while (true) {
        while (Sdl.pollEvent(&event) == 1) {
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

        if (console.paused) {
            _ = try video_context.draw(.{ .timing = .timed });
            continue;
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
