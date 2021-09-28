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
const getMaskBool = flags_.getMaskBool;

pub fn Ppu(comptime config: Config) type {
    return struct {
        const Self = @This();

        cart: *Cart(config),
        cpu: *Cpu(config),
        reg: Registers(config),
        mem: Memory(config),

        scanline: u9 = 0,
        cycle: u9 = 0,

        // internal registers
        v: Address = .{ .value = 0 },
        t: Address = .{ .value = 0 },
        x: u3 = 0,
        w: bool = false,

        sprite_list: SpriteList = SpriteList{},
        scanline_sprites: ScanlineSprites = std.mem.zeroes(ScanlineSprites),

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

        pub fn deinit(_: Self) void {}

        fn evaluateSpritesFrame(self: *Self) void {
            self.sprite_list.reset();

            var i: usize = 0;
            while (i < 256) : (i += 4) {
                if (self.mem.oam[i] < 0xef) {
                    self.sprite_list.addSprite(.{
                        .y = self.mem.oam[i],
                        .tile_index = self.mem.oam[i + 1],
                        .attributes = self.mem.oam[i + 2],
                        .x = self.mem.oam[i + 3],
                        .is_sprite_0 = i == 0,
                    });
                }
            }

            self.sprite_list.sort();
        }

        fn evaluateSpritesScanline(self: *Self) void {
            const tall_sprites = self.reg.getFlag(.{ .flags = "H" });
            self.sprite_list.setYCutoff(@intCast(i16, self.scanline) - if (tall_sprites) @as(i16, 16) else 8);

            self.scanline_sprites.sprite_0_index = null;
            const unevaluated_sprites = self.sprite_list.getScanlineSprites(@truncate(u8, self.scanline));
            for (unevaluated_sprites) |sprite, i| {
                const y_offset_16 =
                    if (getMaskBool(u8, sprite.attributes, 0x80))
                    @truncate(u4, sprite.y -% self.scanline)
                else
                    @truncate(u4, (self.scanline - sprite.y) -% 1);
                const y_offset = @truncate(u3, y_offset_16);

                const tile_offset = @as(u14, sprite.tile_index) << 4;
                const pattern_offset = blk: {
                    if (tall_sprites) {
                        const bank = @as(u14, sprite.tile_index & 1) << 12;
                        const tile_offset_16 = tile_offset & ~@as(u14, 0x10);

                        if (y_offset_16 < 8) {
                            break :blk bank | tile_offset_16;
                        } else {
                            break :blk bank | tile_offset_16 | 0x10;
                        }
                    } else if (self.reg.getFlag(.{ .field = "ppu_ctrl", .flags = "S" })) {
                        break :blk 0x1000 | tile_offset;
                    } else {
                        break :blk tile_offset;
                    }
                };

                const pattern_byte_low = blk: {
                    var byte = self.mem.read(pattern_offset | y_offset);
                    if (sprite.attributes & 0x40 != 0) {
                        byte = @bitReverse(u8, byte);
                    }
                    break :blk byte;
                };
                const pattern_byte_high = blk: {
                    var byte = self.mem.read(pattern_offset | y_offset | 8);
                    if (sprite.attributes & 0x40 != 0) {
                        byte = @bitReverse(u8, byte);
                    }
                    break :blk byte;
                };
                self.scanline_sprites.sprite_pattern_srs1[i].load(pattern_byte_low);
                self.scanline_sprites.sprite_pattern_srs2[i].load(pattern_byte_high);
                self.scanline_sprites.sprite_attributes[i] = sprite.attributes;
                self.scanline_sprites.sprite_x_positions[i] = sprite.x;

                if (sprite.is_sprite_0) {
                    self.scanline_sprites.sprite_0_index = i;
                }
            }
            self.scanline_sprites.sprite_count = unevaluated_sprites.len;
        }

        fn incCoarseX(self: *Self) void {
            if ((self.v.value & @as(u15, 0x1f)) == 0x1f) {
                self.v.value = (self.v.value & ~@as(u15, 0x1f)) ^ 0x400;
            } else {
                self.v.value +%= 1;
            }
        }

        fn incCoarseY(self: *Self) void {
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

        fn renderingEnabled(self: Self) bool {
            return self.reg.getFlags(.{ .flags = "sb" }) != 0;
        }

        pub fn runCycle(self: *Self) void {
            switch (self.scanline) {
                0...239 => self.runVisibleScanlineCycle(),
                240 => {},
                241...260 => {},
                261 => if (self.renderingEnabled() and self.scanline == 261 and self.cycle >= 280 and self.cycle <= 304) {
                    // set coarse y
                    setMask(u15, &self.v.value, self.t.value, 0x7be0);
                } else {
                    self.runVisibleScanlineCycle();
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
                self.evaluateSpritesScanline();
            }

            if (self.scanline == 241 and self.cycle == 1) {
                self.reg.setFlag(.{ .field = "ppu_status", .flags = "V" }, true);
                if (self.reg.getFlag(.{ .field = "ppu_ctrl", .flags = "V" })) {
                    self.cpu.setNmi();
                }
                self.present_frame = true;
            } else if (self.scanline == 261 and self.cycle == 1) {
                self.reg.setFlags(.{ .field = "ppu_status", .flags = "VS" }, 0);
                self.evaluateSpritesFrame();
            }
        }

        fn runVisibleScanlineCycle(self: *Self) void {
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
                setMask(u15, &self.v.value, self.t.value, 0x41f);
            }
        }

        fn getBgPattern(self: Self, reverted_v: Address) u2 {
            if (!self.reg.getFlag(.{ .flags = "b" })) {
                return 0;
            }

            const nametable_byte: u14 = self.mem.peek(0x2000 | @truncate(u14, reverted_v.value));
            const addr = (nametable_byte << 4) | reverted_v.fineY();
            const offset = if (self.reg.getFlag(.{ .field = "ppu_ctrl", .flags = "B" })) @as(u14, 0x1000) else 0;
            const pattern_table_byte1 = self.mem.peek(addr | offset);
            const pattern_table_byte2 = self.mem.peek(addr | 8 | offset);
            const p1: u1 = @truncate(u1, pattern_table_byte1 >> (7 - @truncate(u3, self.cycle +% self.x)));
            const p2: u1 = @truncate(u1, pattern_table_byte2 >> (7 - @truncate(u3, self.cycle +% self.x)));

            return p1 | (@as(u2, p2) << 1);
        }

        fn getSpriteIndex(self: *Self) ?u8 {
            if (!self.reg.getFlag(.{ .flags = "s" })) {
                return null;
            }

            const x = self.cycle;
            var index: ?u8 = null;

            var i: usize = 0;
            while (i < self.scanline_sprites.sprite_count) : (i += 1) {
                const sprite_x = self.scanline_sprites.sprite_x_positions[i];
                if (sprite_x > x -% 8 and sprite_x <= x) {
                    self.scanline_sprites.sprite_pattern_srs1[i].feed();
                    self.scanline_sprites.sprite_pattern_srs2[i].feed();
                    if (index == null) {
                        index = @truncate(u8, i);
                    }
                }
            }

            return index;
        }

        fn drawPixel(self: *Self) void {
            const reverted_v = blk: {
                var old_v = self.v;
                const sub: u2 = if (7 - @truncate(u3, self.cycle) >= self.x) 2 else 1;
                if (old_v.coarseX() < sub) {
                    old_v.value ^= 0x400;
                }
                const new_coarse_x = old_v.coarseX() -% sub;
                old_v.value = (old_v.value & ~@as(u15, 0x1f)) | new_coarse_x;
                break :blk old_v;
            };

            const bg_pattern_index = self.getBgPattern(reverted_v);
            const sprite_index = self.getSpriteIndex();

            var sprite_behind: bool = undefined;
            var sprite_pattern_index: u2 = 0;
            if (sprite_index) |i| {
                sprite_behind = getMaskBool(u8, self.scanline_sprites.sprite_attributes[i], 0x20);
                const p1 = self.scanline_sprites.sprite_pattern_srs1[i].get();
                const p2 = self.scanline_sprites.sprite_pattern_srs2[i].get();
                sprite_pattern_index = p1 | (@as(u2, p2) << 1);
            }

            const addr = blk: {
                if (bg_pattern_index == 0 and sprite_pattern_index == 0) {
                    break :blk 0x3f00;
                } else {
                    var pattern_index: u2 = undefined;
                    var attribute_index: u14 = undefined;
                    var palette_base: u14 = undefined;
                    if (sprite_pattern_index != 0 and bg_pattern_index != 0) {
                        if (self.scanline_sprites.sprite_0_index) |i| {
                            if (sprite_index.? == i) {
                                self.reg.setFlag(.{ .field = "ppu_status", .flags = "S" }, true);
                            }
                        }
                    }
                    if (sprite_pattern_index != 0 and !(sprite_behind and bg_pattern_index != 0)) {
                        pattern_index = sprite_pattern_index;
                        attribute_index = self.scanline_sprites.sprite_attributes[sprite_index.?];
                        palette_base = 0x3f10;
                    } else {
                        pattern_index = bg_pattern_index;
                        const attribute_table_byte = self.mem.read(@as(u14, 0x23c0) |
                            (@as(u14, reverted_v.nametableSelect()) << 10) |
                            ((@as(u14, reverted_v.coarseY()) << 1) & 0x38) |
                            ((reverted_v.coarseX() >> 2) & 7));

                        const x_quadrant = reverted_v.value & 2;
                        const y_quadrant = (reverted_v.value >> 4) & 4;
                        const shift = @truncate(u3, x_quadrant | y_quadrant);

                        attribute_index = @truncate(u2, attribute_table_byte >> shift);

                        palette_base = 0x3f00;
                    }

                    break :blk palette_base | (attribute_index << 2) | pattern_index;
                }
            };

            const palette_byte = self.mem.peek(addr);
            self.frame_buffer.putPixel(self.cycle, self.scanline, common.palette[palette_byte]);
        }
    };
}

const SpritePatternShiftRegister = struct {
    bits: u8 = 0,
    output_bit: u1 = 0,

    fn feed(self: *SpritePatternShiftRegister) void {
        self.output_bit = @truncate(u1, (self.bits & 0x80) >> 7);
        self.bits <<= 1;
    }

    fn load(self: *SpritePatternShiftRegister, byte: u8) void {
        self.bits = byte;
    }

    fn get(self: SpritePatternShiftRegister) u1 {
        return self.output_bit;
    }
};

// contains all sprites visible on screen sorted by y position
// initially goes from 0..last_sprite, as setYCutoff is called,
// start_index starts the slice of sprites considered only at
// sprites where y is on or below the current scanline
const SpriteList = struct {
    sprites: [64]Sprite = [_]Sprite{Sprite{}} ** 64,
    start_index: usize = 0,
    end_index: usize = 0,

    const Sprite = struct {
        y: u8 = 0xff,
        tile_index: u8 = 0xff,
        attributes: u8 = 0xff,
        x: u8 = 0xff,
        is_sprite_0: bool = false,
    };

    fn reset(self: *SpriteList) void {
        self.start_index = 0;
        self.end_index = 0;
    }

    fn addSprite(self: *SpriteList, sprite: Sprite) void {
        self.sprites[self.end_index] = sprite;
        self.end_index += 1;
    }

    fn sort(self: *SpriteList) void {
        const Context = struct {
            fn cmp(_: @This(), lhs: Sprite, rhs: Sprite) bool {
                return lhs.y < rhs.y;
            }
        };
        std.sort.sort(Sprite, self.sprites[0..self.end_index], Context{}, Context.cmp);
    }

    fn setYCutoff(self: *SpriteList, y: i16) void {
        var i: usize = 0;
        for (self.sprites[self.start_index..self.end_index]) |sprite| {
            if (sprite.y >= y) {
                break;
            }
            i += 1;
        }
        self.start_index += i;
    }

    fn getScanlineSprites(self: SpriteList, y: u8) []const Sprite {
        var i: usize = 0;
        for (self.sprites[self.start_index..self.end_index]) |sprite| {
            if (sprite.y >= y or i == 8) {
                break;
            }
            i += 1;
        }
        return self.sprites[self.start_index..(self.start_index + i)];
    }
};

const ScanlineSprites = struct {
    sprite_pattern_srs1: [8]SpritePatternShiftRegister,
    sprite_pattern_srs2: [8]SpritePatternShiftRegister,
    sprite_attributes: [8]u8,
    sprite_x_positions: [8]u8,
    sprite_0_index: ?usize,

    sprite_count: usize,
};

fn Registers(comptime config: Config) type {
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
                    const prev = self.ppu_data;
                    self.ppu_data = ppu.mem.read(@truncate(u14, ppu.v.value));
                    ppu.v.value +%= if (self.getFlag(.{ .flags = "I" })) @as(u8, 32) else 1;
                    return prev;
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
                    setMask(u15, &ppu.t.value, (val_u15 & 3) << 10, 0b000_1100_0000_0000);
                },
                4 => {
                    ppu.mem.oam[self.oam_addr] = val;
                    self.oam_addr +%= 1;
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
                    setMask(u15, &ppu.t.value, (val_u15 & 0x3f) << 8, 0b0111_1111_0000_0000);
                    ppu.w = true;
                } else {
                    setMask(u15, &ppu.t.value, val_u15, 0xff);
                    ppu.v.value = ppu.t.value;
                    ppu.w = false;
                },
                7 => {
                    ppu.mem.write(@truncate(u14, ppu.v.value), val);
                    ppu.v.value +%= if (self.getFlag(.{ .flags = "I" })) @as(u8, 32) else 1;
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

fn Memory(comptime config: Config) type {
    return struct {
        const Self = @This();

        cart: *Cart(config),
        nametables: [0x1000]u8,
        palettes: [0x20]u8,
        oam: [0x100]u8,

        fn init(cart: *Cart(config)) Self {
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
                0x2000...0x3eff => self.nametables[self.cart.mirrorNametable(addr)],
                0x3f00...0x3fff => if (addr & 3 == 0) self.palettes[addr & 0x0c] else self.palettes[addr & 0x1f],
            };
        }

        pub fn write(self: *Self, addr: u14, val: u8) void {
            switch (addr) {
                0x0000...0x1fff => self.cart.writeChr(addr, val),
                0x2000...0x3eff => self.nametables[self.cart.mirrorNametable(addr)] = val,
                0x3f00...0x3fff => if (addr & 3 == 0) {
                    self.palettes[addr & 0x0c] = val;
                } else {
                    self.palettes[addr & 0x1f] = val;
                },
            }
        }
    };
}
