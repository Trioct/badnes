const std = @import("std");
const testing = std.testing;

const Console = @import("console.zig").Console;
const video = @import("video.zig");
const audio = @import("audio.zig");

test "NesTest.nes basic cpu accuracy" {
    var video_context = try video.Context(.Pure).init(testing.allocator);
    defer video_context.deinit(testing.allocator);

    var audio_context = try audio.Context(.Pure).init(testing.allocator);
    defer audio_context.deinit(testing.allocator);

    var console = Console(.{ .precision = .Accurate, .method = .Pure }).alloc();
    console.init(video_context.frame_buffer, &audio_context);
    defer console.deinit(testing.allocator);

    try console.loadRom(testing.allocator, "roms/tests/nestest.nes");
    console.cpu.reset();
    console.controller.holdButton("S");

    while (console.cpu.cycles < 700000) {
        console.cpu.runInstruction();
    }

    try testing.expectEqual(@as(u8, 0x00), console.cpu.mem.peek(0x0000));
}

test {
    _ = @import("apu.zig");
    _ = @import("audio.zig");
    _ = @import("cart.zig");
    _ = @import("console.zig");
    _ = @import("controller.zig");
    _ = @import("cpu.zig");
    _ = @import("flags.zig");
    _ = @import("ines.zig");
    _ = @import("instruction.zig");
    _ = @import("main.zig");
    _ = @import("mapper/common.zig");
    _ = @import("mapper/nrom.zig");
    _ = @import("mapper.zig");
    _ = @import("ppu/accurate.zig");
    _ = @import("ppu/common.zig");
    _ = @import("ppu/fast.zig");
    _ = @import("ppu.zig");
    _ = @import("tests.zig");
    _ = @import("video.zig");
}
