const std = @import("std");
const FrameBuffer = @import("../video.zig").FrameBuffer;

const console_ = @import("../console.zig");
const Config = console_.Config;
const Console = console_.Console;

const Cart = @import("../cart.zig").Cart;
const Cpu = @import("../cpu.zig").Cpu;

const common = @import("common.zig");
const Address = common.Address;

const flags_ = @import("../flags.zig");
const FieldFlags = flags_.FieldFlags;
const setMask = flags_.setMask;

pub fn Ppu(comptime config: Config) type {
    return struct {
        const Self = @This();
        pub const precision = config.precision;

        cart: *Cart(config),
        cpu: *Cpu(config),
        reg: Registers(config),
        mem: Memory(config),

        scanline: u9 = 0,
        cycle: u9 = 0,
        odd_frame: bool = false,

        // internal registers
        v: Address = .{ .value = 0 },
        t: Address = .{ .value = 0 },
        x: u3 = 0,
        w: bool = false,

        frame_buffer: FrameBuffer(config.method),
        present_frame: bool = false,

        pub fn init(console: *Console(config), frame_buffer: FrameBuffer(config.method)) Self {
            return Self{
                .cart = &console.cart,
                .cpu = &console.cpu,
                .reg = std.mem.zeroes(Registers(config)),
                .mem = Memory(config).init(&console.cart),
                .frame_buffer = frame_buffer,
            };
        }

        pub fn deinit(self: Self) void {
            _ = self;
        }

        pub fn incCoarseX(self: *Self) void {
            if ((self.v.value & @as(u15, 0x1f)) == 0x1f) {
                self.v.value = (self.v.value & ~@as(u15, 0x1f)) ^ 0x400;
            } else {
                self.v.value +%= 1;
            }
        }

        pub fn incCoarseY(self: *Self) void {
            if ((self.v.value & 0x7000) != 0x7000) {
                self.v.value += 0x1000;
            } else {
                self.v.value &= ~@as(u15, 0x7000);
                var y = (self.v.value & @as(u15, 0x03e0)) >> 5;
                if (y == 29) {
                    y = 0;
                    self.v.value ^= 0x0800;
                } else if (y == 31) {
                    y = 0;
                } else {
                    y += 1;
                }
                self.v.value = (self.v.value & ~@as(u15, 0x03e0)) | (y << 5);
            }
        }

        pub fn renderingEnabled(self: Self) bool {
            return self.reg.getFlags(.{ .flags = "sb" }) != 0;
        }

        pub fn runCycle(self: *Self) void {
            switch (self.scanline) {
                0...239 => self.runVisibleScanlineCycle(),
                240 => {},
                241...260 => {},
                261 => {
                    if (self.cycle == 339 and self.odd_frame) {
                        self.cycle += 1;
                    }

                    if (self.renderingEnabled() and self.scanline == 261 and self.cycle >= 280 and self.cycle <= 304) {
                        // set coarse y
                        const mask = @as(u15, 0x7be0);
                        self.v.value = (self.v.value & ~mask) | (self.t.value & mask);
                    } else {
                        self.runVisibleScanlineCycle();
                    }
                },
                else => unreachable,
            }

            if (self.renderingEnabled() and self.scanline < 240 and self.cycle < 256) {
                self.drawPixel();
            }

            self.cycle += 1;
            if (self.cycle == 341) {
                self.cycle = 0;
                self.scanline = (self.scanline + 1) % 262;
            }

            if (self.scanline == 241 and self.cycle == 1) {
                self.reg.setFlag(.{ .field = "ppu_status", .flags = "V" }, true);
                if (self.reg.getFlag(.{ .field = "ppu_ctrl", .flags = "V" })) {
                    self.cpu.setNmi();
                }
                self.present_frame = true;
            } else if (self.scanline == 261 and self.cycle == 1) {
                self.reg.setFlags(.{ .field = "ppu_status", .flags = "VS" }, 0);
                self.odd_frame = !self.odd_frame;
            }
        }

        pub fn runVisibleScanlineCycle(self: *Self) void {
            if (!self.renderingEnabled() or self.cycle == 0) {
                return;
            }

            if (self.cycle > 257 and self.cycle < 321) {
                self.reg.oam_addr = 0;
                return;
            }

            if ((self.cycle & 255) == 0) {
                self.incCoarseY();
            } else if ((self.cycle & 7) == 0) {
                self.incCoarseX();
            } else if (self.cycle == 257) {
                // set coarse x
                const mask = @as(u15, 0x41f);
                self.v.value = (self.v.value & ~mask) | (self.t.value & mask);
            }
        }

        fn drawPixel(self: *Self) void {
            const reverted_v = blk: {
                var old_v = self.v;
                if (old_v.coarseX() < 2) {
                    old_v.value ^= 0x400;
                }
                const new_coarse_x = old_v.coarseX() -% 2;
                old_v.value = (old_v.value & ~@as(u15, 0x1f)) | new_coarse_x;
                break :blk old_v;
            };

            const bg_attribute_table_index: u2 = blk: {
                const nametable_byte: u14 = self.mem.peek(0x2000 | @truncate(u14, reverted_v.value));
                const addr = (nametable_byte << 4) | reverted_v.fineY();
                const offset = if (self.reg.getFlag(.{ .field = "ppu_ctrl", .flags = "B" })) @as(u14, 0x1000) else 0;
                const pattern_table_byte1 = self.mem.peek(addr | offset);
                const pattern_table_byte2 = self.mem.peek(addr | 8 | offset);
                const pattern_table_bit1: u1 = @truncate(u1, pattern_table_byte1 >> (7 - @truncate(u3, self.cycle)));
                const pattern_table_bit2: u1 = @truncate(u1, pattern_table_byte2 >> (7 - @truncate(u3, self.cycle)));
                break :blk pattern_table_bit1 | (@as(u2, pattern_table_bit2) << 1);
            };

            const x = self.cycle;
            const y = (@as(u8, reverted_v.coarseY()) << 3) | reverted_v.fineY();
            for (@ptrCast([*]u32, @alignCast(4, self.mem.oam[0..]))[0..64]) |cell| {
                const cell_x = @truncate(u8, cell >> 24);
                const cell_y = @truncate(u8, cell);
                if (cell_x < x and cell_x >= x -% 8 and cell_y <= y and cell_y > y -% 8) {
                    const tile_index = @truncate(u14, (cell >> 8) & 0xff);
                    const attributes = @truncate(u8, cell >> 16);

                    const addr = (tile_index << 4) | @truncate(u3, y - cell_y);
                    const offset = if (self.reg.getFlag(.{ .field = "ppu_ctrl", .flags = "S" })) @as(u14, 0x1000) else 0;
                    const pattern_table_byte1 = self.mem.peek(addr | offset);
                    const pattern_table_byte2 = self.mem.peek(addr | 8 | offset);
                    const shift = blk: {
                        if (attributes >> 6 == 0) {
                            break :blk @truncate(u3, cell_x) -% @truncate(u3, self.cycle);
                        } else {
                            break :blk @truncate(u3, self.cycle) -% @truncate(u3, cell_x) -% 1;
                        }
                    };
                    const pattern_table_bit1: u1 = @truncate(u1, pattern_table_byte1 >> shift);
                    const pattern_table_bit2: u1 = @truncate(u1, pattern_table_byte2 >> shift);
                    const sprite_attribute_table_index: u2 = pattern_table_bit1 | (@as(u2, pattern_table_bit2) << 1);
                    if (sprite_attribute_table_index == 0) {
                        continue;
                    } else if (bg_attribute_table_index != 0) {
                        self.reg.setFlag(.{ .field = "ppu_status", .flags = "S" }, true);
                    }

                    const palette_index = @as(u14, ((attributes & 3) << 2) | sprite_attribute_table_index);
                    const palette_byte = self.mem.peek(0x3f10 | palette_index);

                    self.frame_buffer.putPixel(self.cycle, self.scanline, common.palette[palette_byte]);
                    return;
                }
            }

            const attribute_table_byte: u8 = self.mem.peek(@truncate(u14, 0x23c0 |
                (reverted_v.value & 0x0c00) |
                ((reverted_v.value >> 4) & 0x38) |
                ((reverted_v.value >> 2) & 7)));

            const palette_index = @as(u14, ((attribute_table_byte & 3) << 2) | bg_attribute_table_index);
            const palette_byte = self.mem.peek(0x3f00 | palette_index);

            self.frame_buffer.putPixel(self.cycle, self.scanline, common.palette[palette_byte]);
        }
    };
}

pub fn Registers(comptime config: Config) type {
    return packed struct {
        const Self = @This();

        ppu_ctrl: u8,
        ppu_mask: u8,
        ppu_status: u8,
        oam_addr: u8,
        oam_data: u8,
        ppu_scroll: u8,
        ppu_addr: u8,
        ppu_data: u8,

        const ff_masks = common.RegisterMasks(Self){};

        // flag functions do not have side effects even when they should
        fn getFlag(self: Self, comptime flags: FieldFlags) bool {
            return ff_masks.getFlag(self, flags);
        }

        fn getFlags(self: Self, comptime flags: FieldFlags) u8 {
            return ff_masks.getFlags(self, flags);
        }

        fn setFlag(self: *Self, comptime flags: FieldFlags, val: bool) void {
            return ff_masks.setFlag(self, flags, val);
        }

        fn setFlags(self: *Self, comptime flags: FieldFlags, val: u8) void {
            return ff_masks.setFlags(self, flags, val);
        }

        pub fn peek(self: Self, i: u3) u8 {
            return @truncate(u8, (@bitCast(u64, self) >> (@as(u6, i) * 8)));
        }

        pub fn read(self: *Self, i: u3) u8 {
            var ppu = @fieldParentPtr(Ppu(config), "reg", self);
            const val = self.peek(i);
            switch (i) {
                2 => {
                    ppu.reg.setFlag(.{ .field = "ppu_status", .flags = "V" }, false);
                    ppu.w = false;
                },
                4 => {
                    return ppu.mem.oam[self.oam_addr];
                },
                7 => {
                    self.ppu_data = ppu.mem.read(@truncate(u14, ppu.v.value));
                    return self.ppu_data;
                },
                else => {},
            }
            return val;
        }

        pub fn write(self: *Self, i: u3, val: u8) void {
            var ppu = @fieldParentPtr(Ppu(config), "reg", self);
            var val_u15 = @as(u15, val);
            switch (i) {
                0 => {
                    const mask = ~@as(u15, 0b000_1100_0000_0000);
                    ppu.t.value = (ppu.t.value & mask) | ((val_u15 & 3) << 10);
                },
                4 => {
                    ppu.mem.oam[self.oam_addr] = val;
                },
                5 => if (!ppu.w) {
                    ppu.t.value = (ppu.t.value & ~@as(u15, 0x1f)) | (val >> 3);
                    ppu.x = @truncate(u3, val);
                    ppu.w = true;
                } else {
                    const old_t = ppu.t.value & ~@as(u15, 0b111_0011_1110_0000);
                    ppu.t.value = old_t | ((val_u15 & 0xf8) << 5) | ((val_u15 & 7) << 12);
                    ppu.w = false;
                },
                6 => if (!ppu.w) {
                    const mask = ~@as(u15, 0b0111_1111_0000_0000);
                    ppu.t.value = (ppu.t.value & mask) | ((val_u15 & 0x3f) << 8);
                    ppu.w = true;
                } else {
                    const mask = ~@as(u15, 0xff);
                    ppu.t.value = (ppu.t.value & mask) | val_u15;
                    ppu.v.value = ppu.t.value;
                    ppu.w = false;
                },
                7 => {
                    ppu.mem.write(@truncate(u14, ppu.v.value), val);
                    ppu.v.value +%= if (ppu.reg.getFlag(.{ .flags = "I" })) @as(u8, 32) else 1;
                },
                else => {},
            }
            const bytes = @bitCast(u64, self.*);
            const shift = @as(u6, i) * 8;
            const mask = @as(u64, 0xff) << shift;
            self.* = @bitCast(Self, (bytes & ~mask) | @as(u64, val) << shift);
        }
    };
}

pub fn Memory(comptime config: Config) type {
    return struct {
        const Self = @This();

        cart: *Cart(config),
        nametables: [0x1000]u8,
        palettes: [0x20]u8,
        oam: [0x100]u8,

        pub fn init(cart: *Cart(config)) Self {
            return Self{
                .cart = cart,
                .nametables = std.mem.zeroes([0x1000]u8),
                .palettes = std.mem.zeroes([0x20]u8),
                .oam = std.mem.zeroes([0x100]u8),
            };
        }

        pub const peek = read;

        pub fn read(self: Self, addr: u14) u8 {
            return switch (addr) {
                0x0000...0x1fff => self.cart.readChr(addr),
                0x2000...0x3eff => self.nametables[addr & 0xfff],
                0x3f00...0x3fff => if (addr & 3 == 0) self.palettes[0] else self.palettes[addr & 0x1f],
            };
        }

        pub fn write(self: *Self, addr: u14, val: u8) void {
            switch (addr) {
                0x2000...0x3eff => self.nametables[addr & 0xfff] = val,
                0x3f00...0x3fff => if (addr & 3 == 0) {
                    self.palettes[0] = val;
                } else {
                    self.palettes[addr & 0x1f] = val;
                },
                0x0000...0x1fff => {
                    std.log.err("Unimplemented write memory address ({x:0>4})", .{addr});
                },
            }
        }
    };
}
