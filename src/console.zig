const std = @import("std");
const Allocator = std.mem.Allocator;

const ines = @import("ines.zig");
const Cart = @import("cart.zig").Cart;
const Ppu = @import("ppu.zig").Ppu;
const Cpu = @import("cpu.zig").Cpu;
const Apu = @import("apu.zig").Apu;
const Controller = @import("controller.zig").Controller;

const video = @import("video.zig");
const audio = @import("audio.zig");

pub const Precision = enum {
    fast,
    accurate,
};

pub const IoMethod = enum {
    pure,
    sdl,
};

pub const Config = struct {
    precision: Precision,
    method: IoMethod,
};

pub fn Console(comptime config: Config) type {
    return struct {
        const Self = @This();

        allocator: *Allocator,

        cart: Cart(config),
        ppu: Ppu(config),
        cpu: Cpu(config),
        apu: Apu(config),
        controller: Controller(config.method),

        pixel_buffer: *video.PixelBuffer(config.method),
        audio_context: *audio.Context(config.method),

        pub fn alloc() Self {
            return Self{
                .allocator = undefined,
                .cart = undefined,
                .ppu = undefined,
                .cpu = undefined,
                .apu = undefined,
                .controller = undefined,
                .pixel_buffer = undefined,
                .audio_context = undefined,
            };
        }

        pub fn init(
            self: *Self,
            allocator: *Allocator,
            pixel_buffer: *video.PixelBuffer(config.method),
            audio_context: *audio.Context(config.method),
        ) void {
            self.allocator = allocator;

            self.cart = Cart(config).init();
            self.ppu = Ppu(config).init(self, pixel_buffer);
            self.cpu = Cpu(config).init(self);
            self.apu = Apu(config).init(self, audio_context);
            self.controller = Controller(config.method){};

            self.pixel_buffer = pixel_buffer;
            self.audio_context = audio_context;
        }

        pub fn deinit(self: Self) void {
            self.cart.deinit(self.allocator);
            self.ppu.deinit();
            self.cpu.deinit();
        }

        pub fn loadRom(self: *Self, path: []const u8) !void {
            var info = try ines.RomInfo.readFile(self.allocator, path);
            defer info.deinit(self.allocator);
            try self.cart.loadRom(self.allocator, self, &info);
            self.cpu.reset();
        }

        pub fn clearState(self: *Self) void {
            self.deinit();
            self.init(self.allocator, self.pixel_buffer, self.audio_context);
        }
    };
}
