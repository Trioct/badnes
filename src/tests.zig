const std = @import("std");
const testing = std.testing;

const console_ = @import("console.zig");
const Console = console_.Console;
const Precision = console_.Precision;

const video = @import("video.zig");
const audio = @import("audio.zig");

fn testRom(
    comptime precision: Precision,
    comptime rom: []const u8,
    cycles: usize,
    comptime buttons: ?[]const u8,
    expect_addr: u16,
    expect_val: u8,
) !void {
    var video_context = try video.Context(.Pure).init(testing.allocator);
    defer video_context.deinit(testing.allocator);

    var audio_context = try audio.Context(.Pure).init(testing.allocator);
    defer audio_context.deinit(testing.allocator);

    var console = Console(.{ .precision = precision, .method = .Pure }).alloc();
    console.init(video_context.frame_buffer, &audio_context);
    defer console.deinit(testing.allocator);

    try console.loadRom(testing.allocator, "roms/nes-test-roms/" ++ rom);
    console.cpu.reset();
    if (buttons) |b| {
        console.controller.holdButtons(b);
    }

    while (console.cpu.cycles < cycles) {
        console.cpu.runStep();
    }

    try testing.expectEqual(expect_val, console.cpu.mem.peek(expect_addr));
}

fn testBlarggRom(comptime precision: Precision, comptime rom: []const u8, cycles: usize) !void {
    return testRom(precision, rom, cycles, null, 0x00f0, 0x01);
}

test "nestest.nes basic cpu accuracy" {
    try testRom(.Fast, "other/nestest.nes", 700000, "S", 0x0000, 0x00);
    try testRom(.Accurate, "other/nestest.nes", 700000, "S", 0x0000, 0x00);
}

test "blargg apu tests" {
    try testBlarggRom(.Fast, "blargg_apu_2005.07.30/01.len_ctr.nes", 450000);
    try testBlarggRom(.Accurate, "blargg_apu_2005.07.30/01.len_ctr.nes", 450000);

    try testBlarggRom(.Fast, "blargg_apu_2005.07.30/02.len_table.nes", 25000);
    try testBlarggRom(.Accurate, "blargg_apu_2005.07.30/02.len_table.nes", 25000);

    try testBlarggRom(.Fast, "blargg_apu_2005.07.30/03.irq_flag.nes", 220000);
    try testBlarggRom(.Accurate, "blargg_apu_2005.07.30/03.irq_flag.nes", 220000);
}

test "blargg ppu tests" {
    try testBlarggRom(.Accurate, "blargg_ppu_tests_2005.09.15b/vram_access.nes", 120000);
    try testBlarggRom(.Accurate, "blargg_ppu_tests_2005.09.15b/palette_ram.nes", 120000);

    try testBlarggRom(.Fast, "blargg_ppu_tests_2005.09.15b/sprite_ram.nes", 120000);
    try testBlarggRom(.Accurate, "blargg_ppu_tests_2005.09.15b/sprite_ram.nes", 120000);
}

test {
    _ = @import("apu.zig");
    _ = @import("audio.zig");
    _ = @import("cart.zig");
    _ = @import("console.zig");
    _ = @import("controller.zig");
    _ = @import("cpu.zig");
    _ = @import("cpu/accurate.zig");
    _ = @import("cpu/fast.zig");
    _ = @import("flags.zig");
    _ = @import("ines.zig");
    _ = @import("instruction.zig");
    _ = @import("interface.zig");
    _ = @import("main.zig");
    _ = @import("mapper/common.zig");
    _ = @import("mapper/nrom.zig");
    _ = @import("mapper/mmc1.zig");
    _ = @import("mapper.zig");
    _ = @import("ppu/accurate.zig");
    _ = @import("ppu/common.zig");
    _ = @import("ppu/fast.zig");
    _ = @import("ppu.zig");
    _ = @import("video.zig");
}
