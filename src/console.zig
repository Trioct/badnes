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

        cart: Cart(config),
        ppu: Ppu(config),
        cpu: Cpu(config),
        apu: Apu(config),
        controller: Controller(config.method),

        pub fn alloc() Self {
            return Self{
                .cart = undefined,
                .ppu = undefined,
                .cpu = undefined,
                .apu = undefined,
                .controller = undefined,
            };
        }

        pub fn init(
            self: *Self,
            pixel_buffer: *video.PixelBuffer(config.method),
            audio_context: *audio.Context(config.method),
        ) void {
            self.cart = Cart(config).init();
            self.ppu = Ppu(config).init(self, pixel_buffer);
            self.cpu = Cpu(config).init(self);
            self.apu = Apu(config).init(self, audio_context);
            self.controller = Controller(config.method){};
        }

        pub fn deinit(self: Self, allocator: *Allocator) void {
            self.cart.deinit(allocator);
            self.ppu.deinit();
            self.cpu.deinit();
        }

        pub fn loadRom(self: *Self, allocator: *Allocator, path: []const u8) !void {
            var info = try ines.RomInfo.readFile(allocator, path);
            defer info.deinit(allocator);
            return self.cart.loadRom(allocator, self, &info);
        }
    };
}
