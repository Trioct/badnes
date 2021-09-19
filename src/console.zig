const std = @import("std");
const Allocator = std.mem.Allocator;

const ines = @import("ines.zig");
const Cart = @import("cart.zig").Cart;
const Ppu = @import("ppu.zig").Ppu;
const Cpu = @import("cpu.zig").Cpu;
const Apu = @import("apu.zig").Apu;
const Controller = @import("controller.zig").Controller;

const video = @import("sdl/video.zig");
const audio = @import("sdl/audio.zig");

pub const Precision = enum {
    Fast,
    Accurate,
};

pub const Console = struct {
    cart: Cart,
    ppu: Ppu(.Accurate),
    cpu: Cpu,
    apu: Apu,
    controller: Controller,

    pub fn alloc() Console {
        return Console{
            .cart = undefined,
            .ppu = undefined,
            .cpu = undefined,
            .apu = undefined,
            .controller = undefined,
        };
    }

    pub fn init(self: *Console, frame_buffer: video.FrameBuffer, audio_context: *audio.AudioContext) void {
        self.cart = Cart.init();
        self.ppu = Ppu(.Accurate).init(self, frame_buffer);
        self.cpu = Cpu.init(self);
        self.apu = Apu.init(audio_context);
        self.controller = Controller{};
    }

    pub fn deinit(self: Console, allocator: *Allocator) void {
        self.cart.deinit(allocator);
        self.ppu.deinit();
        self.cpu.deinit();
    }

    pub fn loadRom(self: *Console, allocator: *Allocator, path: []const u8) !void {
        var info = try ines.RomInfo.readFile(allocator, path);
        defer info.deinit(allocator);
        return self.cart.loadRom(allocator, self, &info);
    }
};
