const std = @import("std");
const Allocator = std.mem.Allocator;

const ines = @import("ines.zig");
const Cpu = @import("cpu.zig").Cpu;
const Ppu = @import("ppu.zig").Ppu;
const Cart = @import("cart.zig").Cart;
const Controller = @import("controller.zig").Controller;

const sdl = @import("sdl.zig");

pub const Precision = enum {
    Fast,
    Accurate,
};

const Console = struct {
    cart: Cart,
    ppu: Ppu(.Accurate),
    cpu: Cpu,
    controller: Controller,

    pub fn alloc() Console {
        return Console{
            .cart = undefined,
            .ppu = undefined,
            .cpu = undefined,
            .controller = undefined,
        };
    }

    pub fn init(self: *Console, frame_buffer: sdl.FrameBuffer) void {
        self.cart = Cart.init();
        self.ppu = Ppu(.Accurate).init(&self.cart, &self.cpu, frame_buffer);
        self.cpu = Cpu.init(&self.cart, &self.ppu, &self.controller);
        self.controller = Controller{};
    }

    pub fn deinit(self: Console, allocator: *Allocator) void {
        self.cart.deinit(allocator);
        self.ppu.deinit();
        self.cpu.deinit();
    }
};

pub fn main() anyerror!void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.detectLeaks();

    var allocator = &gpa.allocator;

    try sdl.init(.{sdl.c.SDL_INIT_VIDEO | sdl.c.SDL_INIT_EVENTS});
    defer sdl.quit();

    var sdl_context = try sdl.SdlContext.init("Badnes", 0, 0, 256 * 3, 240 * 3);
    defer sdl_context.deinit();

    var console = Console.alloc();
    console.init(sdl_context.frame_buffer);
    defer console.deinit(allocator);

    //const rom_name = "roms/tests/scanline.nes";
    const rom_name = "roms/no-redist/Mario Bros. (World).nes";
    //const rom_name = "roms/no-redist/Donkey Kong (JU).nes";
    //const rom_name = "roms/no-redist/Super Mario Bros. (World).nes";
    var info = try ines.RomInfo.readFile(allocator, rom_name);
    defer info.deinit(allocator);

    try console.cart.loadRom(allocator, &info);
    console.cpu.reset();

    var event: sdl.c.SDL_Event = undefined;
    var then = std.time.nanoTimestamp();
    var total_time: i128 = 0;
    var frames: usize = 0;
    mloop: while (true) {
        while (sdl.pollEvent(.{&event}) == 1) {
            switch (event.type) {
                sdl.c.SDL_KEYUP => switch (event.key.keysym.sym) {
                    sdl.c.SDLK_q => break :mloop,
                    else => {},
                },
                sdl.c.SDL_QUIT => break :mloop,
                else => {},
            }
        }
        if (console.ppu.present_frame) {
            frames += 1;
            console.ppu.present_frame = false;
            try sdl_context.frame_buffer.present(sdl_context.renderer);

            var now = std.time.nanoTimestamp();
            std.time.sleep(@intCast(u64, @maximum(0, (1 * std.time.ns_per_s) / 60 - (now - then))));

            now = std.time.nanoTimestamp();
            total_time += now - then;
            then = now;
            if (total_time > std.time.ns_per_s) {
                std.debug.print("FPS: {}\n", .{frames});
                frames = 0;
                total_time -= std.time.ns_per_s;
            }
        }
        console.cpu.runInstruction(.Fast);
    }
}

test {
    std.testing.refAllDecls(@This());
}
