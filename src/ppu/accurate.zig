const std = @import("std");
const PixelBuffer = @import("../video.zig").PixelBuffer;

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
        oam: Oam,

        scanline: u9 = 0,
        cycle: u9 = 0,
        odd_frame: bool = false,

        // internal registers
        vram_addr: Address = .{ .value = 0 },
        vram_temp: Address = .{ .value = 0 },
        fine_x: u3 = 0,

        current_nametable_byte: u8 = 0,

        pattern_sr1: BgPatternShiftRegister = .{},
        pattern_sr2: BgPatternShiftRegister = .{},

        attribute_sr1: AttributeShiftRegister = .{},
        attribute_sr2: AttributeShiftRegister = .{},

        pixel_buffer: *PixelBuffer(config.method),
        present_frame: bool = false,

        pub fn init(console: *Console(config), pixel_buffer: *PixelBuffer(config.method)) Self {
            return Self{
                .cart = &console.cart,
                .cpu = &console.cpu,
                .reg = Registers(config).init(&console.ppu),
                .mem = Memory(config).init(&console.cart),
                .oam = std.mem.zeroes(Oam),
                .pixel_buffer = pixel_buffer,
            };
        }

        pub fn deinit(_: Self) void {}

        fn incCoarseX(self: *Self) void {
            if ((self.vram_addr.value & @as(u15, 0x1f)) == 0x1f) {
                self.vram_addr.value = (self.vram_addr.value & ~@as(u15, 0x1f)) ^ 0x400;
            } else {
                self.vram_addr.value +%= 1;
            }
        }

        fn incCoarseY(self: *Self) void {
            if ((self.vram_addr.value & 0x7000) != 0x7000) {
                self.vram_addr.value += 0x1000;
            } else {
                self.vram_addr.value &= ~@as(u15, 0x7000);
                var y = (self.vram_addr.value & @as(u15, 0x03e0)) >> 5;
                if (y == 29) {
                    y = 0;
                    self.vram_addr.value ^= 0x0800;
                } else if (y == 31) {
                    y = 0;
                } else {
                    y += 1;
                }
                setMask(u15, &self.vram_addr.value, y << 5, 0x03e0);
            }
        }

        fn renderingEnabled(self: Self) bool {
            return self.reg.getFlags(null, "sb") != 0;
        }

        fn onRenderScanline(self: Self) bool {
            return self.scanline < 240 or self.scanline == 261;
        }

        fn feedShiftRegisters(self: *Self) void {
            self.pattern_sr1.feed();
            self.pattern_sr2.feed();
            self.attribute_sr1.feed();
            self.attribute_sr2.feed();
        }

        fn loadShiftRegisters(self: *Self) void {
            self.pattern_sr1.load();
            self.pattern_sr2.load();
            self.attribute_sr1.load();
            self.attribute_sr2.load();
        }

        fn fetchNametableByte(self: *Self) void {
            self.current_nametable_byte = self.mem.read(@as(u14, 0x2000) | @as(u12, @truncate(self.vram_addr.value)));
        }

        fn fetchAttributeByte(self: *Self) void {
            const attribute_table_byte: u8 = self.mem.read(@as(u14, 0x23c0) |
                (@as(u14, self.vram_addr.nametableSelect()) << 10) |
                ((@as(u14, self.vram_addr.coarseY()) << 1) & 0x38) |
                ((self.vram_addr.coarseX() >> 2) & 7));

            const x_quadrant = self.vram_addr.value & 2;
            const y_quadrant = (self.vram_addr.value >> 4) & 4;
            const shift: u3 = @truncate(x_quadrant | y_quadrant);
            self.attribute_sr1.prepare(@truncate(attribute_table_byte >> shift));
            self.attribute_sr2.prepare(@truncate(attribute_table_byte >> (shift + 1)));
        }

        fn fetchLowBgTile(self: *Self) void {
            const addr = (@as(u14, self.current_nametable_byte) << 4) | self.vram_addr.fineY();
            const offset = if (self.reg.getFlag(.ppu_ctrl, "B")) @as(u14, 0x1000) else 0;
            const pattern_table_byte = self.mem.read(addr | offset);
            self.pattern_sr1.prepare(pattern_table_byte);
        }

        fn fetchHighBgTile(self: *Self) void {
            const addr = (@as(u14, self.current_nametable_byte) << 4) | self.vram_addr.fineY();
            const offset = if (self.reg.getFlag(.ppu_ctrl, "B")) @as(u14, 0x1000) else 0;
            const pattern_table_byte = self.mem.read(addr | offset | 8);
            self.pattern_sr2.prepare(pattern_table_byte);
        }

        fn fetchNextByte(self: *Self) void {
            if (!((self.cycle >= 1 and self.cycle <= 256) or (self.cycle >= 321 and self.cycle <= 336))) {
                return;
            }

            self.feedShiftRegisters();

            switch (@as(u2, @truncate(self.cycle >> 1))) {
                0 => {
                    self.loadShiftRegisters();
                    self.fetchNametableByte(); // cycle % 8 == 0
                },
                1 => self.fetchAttributeByte(), // cycle % 8 == 2
                2 => self.fetchLowBgTile(), // cycle % 8 == 4
                3 => self.fetchHighBgTile(), // cycle % 8 == 6
            }
        }

        fn spriteEvaluation(self: *Self) void {
            switch (self.cycle) {
                1...64 => if (self.cycle & 1 == 0) {
                    self.oam.secondary[(self.cycle >> 1) - 1] = 0xff;
                },
                65...256 => {
                    if (self.oam.search_finished) {
                        return;
                    }
                    if (self.cycle & 1 == 1) {
                        // read cycle
                        self.oam.readForSecondary();
                        return;
                    } else if (self.oam.primary_index & 3 == 0) {
                        const sprite_height = if (self.reg.getFlag(null, "H")) @as(u5, 16) else 8;
                        // check if y is in range
                        const sprite_y = self.oam.temp_read_byte;
                        if (sprite_y <= self.scanline and @as(u9, sprite_y) + sprite_height > self.scanline) {
                            if (self.oam.primary_index == 0) {
                                self.oam.next_has_sprite_0 = true;
                            }
                            self.oam.storeSecondary();
                        } else {
                            self.oam.primary_index +%= 4;
                        }
                    } else {
                        // copy the rest of bytes 1 <= n <= 3
                        self.oam.storeSecondary();
                        if (self.oam.primary_index & 3 == 0) {
                            self.oam.sprites_found += 1;
                        }
                    }
                    if (self.oam.primary_index == 0 or self.oam.sprites_found == 8) {
                        self.oam.search_finished = true;
                    }
                },
                257...320 => {
                    // not exactly cycle accurate
                    if (self.cycle & 1 != 0 or self.oam.sprite_index == self.oam.sprites_found or
                        self.oam.sprite_index == 8)
                    {
                        return;
                    }
                    const y = self.oam.secondary[self.oam.sprite_index * 4];
                    const tile_index = self.oam.secondary[self.oam.sprite_index * 4 + 1];
                    const attributes = self.oam.secondary[self.oam.sprite_index * 4 + 2];
                    const x = self.oam.secondary[self.oam.sprite_index * 4 + 3];

                    const y_offset_16: u4 =
                        if (getMaskBool(u8, attributes, 0x80))
                        @truncate(~(self.scanline - y))
                    else
                        @truncate(self.scanline - y);
                    const y_offset: u3 = @truncate(y_offset_16);

                    const tile_offset = @as(u14, tile_index) << 4;
                    const pattern_offset = blk: {
                        if (self.reg.getFlag(null, "H")) {
                            const bank = @as(u14, tile_index & 1) << 12;
                            const tile_offset_16 = tile_offset & ~@as(u14, 0x10);

                            if (y_offset_16 < 8) {
                                break :blk bank | tile_offset_16;
                            } else {
                                break :blk bank | tile_offset_16 | 0x10;
                            }
                        } else if (self.reg.getFlag(.ppu_ctrl, "S")) {
                            break :blk 0x1000 | tile_offset;
                        } else {
                            break :blk tile_offset;
                        }
                    };
                    switch (@as(u2, @truncate(self.cycle >> 1))) {
                        0 => {},
                        1 => {
                            self.oam.sprite_x_counters[self.oam.sprite_index] = x;
                            self.oam.sprite_attributes[self.oam.sprite_index] = attributes;
                        },
                        2 => {
                            const pattern_byte = blk: {
                                var byte = self.mem.read(pattern_offset | y_offset);
                                if (attributes & 0x40 != 0) {
                                    byte = @bitReverse(byte);
                                }
                                break :blk byte;
                            };
                            self.oam.sprite_pattern_srs1[self.oam.sprite_index].load(pattern_byte);
                        },
                        3 => {
                            const pattern_byte = blk: {
                                var byte = self.mem.read(pattern_offset | y_offset | 8);
                                if (attributes & 0x40 != 0) {
                                    byte = @bitReverse(byte);
                                }
                                break :blk byte;
                            };
                            self.oam.sprite_pattern_srs2[self.oam.sprite_index].load(pattern_byte);
                            self.oam.sprite_index += 1;
                        },
                    }
                },
                else => {},
            }
        }

        pub fn runCycle(self: *Self) void {
            defer self.runPostCycle();

            if (!(self.onRenderScanline() and self.renderingEnabled())) {
                return;
            }

            self.fetchNextByte();
            if (self.scanline < 240) {
                self.spriteEvaluation();
                if (self.cycle < 256) {
                    self.drawPixel();
                }
            }

            if (self.cycle > 0) {
                if (self.cycle > 257 and self.cycle < 321) {
                    self.reg.oam_addr = 0;

                    if (self.scanline == 261 and self.cycle >= 280 and self.cycle <= 304) {
                        // set coarse and fine y as well as 0x800 (high nametable select bit)
                        setMask(u15, &self.vram_addr.value, self.vram_temp.value, 0x7be0);
                    }
                } else if (self.cycle == 256) {
                    self.incCoarseY();
                } else if ((self.cycle & 7) == 0) {
                    self.incCoarseX();
                } else if (self.cycle == 257) {
                    // set coarse x and 0x400 (low nametable select bit)
                    setMask(u15, &self.vram_addr.value, self.vram_temp.value, 0x41f);
                }
            }
        }

        fn runPostCycle(self: *Self) void {
            if (self.scanline == 261 and self.cycle == 339 and self.odd_frame) {
                self.cycle += 1;
            }

            self.cycle += 1;
            if (self.cycle == 341) {
                self.cycle = 0;
                self.scanline = (self.scanline + 1) % 262;
                self.oam.resetSecondaryTemps();
            }

            if (self.scanline == 241 and self.cycle == 1) {
                self.reg.setFlag(.ppu_status, "V", true);
                if (self.reg.getFlag(.ppu_ctrl, "V")) {
                    self.cpu.setNmi();
                }
                self.present_frame = true;
            } else if (self.scanline == 261 and self.cycle == 1) {
                self.reg.setFlags(.ppu_status, "VS", 0);
                self.odd_frame = !self.odd_frame;
            }
        }

        fn drawPixel(self: *Self) void {
            const bg_pattern_index: u2 = blk: {
                if (self.reg.getFlag(null, "b")) {
                    const p1 = self.pattern_sr1.get(self.fine_x);
                    const p2 = self.pattern_sr2.get(self.fine_x);
                    break :blk p1 | (@as(u2, p2) << 1);
                } else {
                    break :blk 0;
                }
            };

            var sprite_pattern_index: u2 = 0;
            var sprite_attribute_index: u2 = 0;
            var sprite_behind: bool = false;
            if (self.reg.getFlag(null, "s")) {
                var i: usize = 0;
                while (i < self.oam.active_sprites) : (i += 1) {
                    if (sprite_pattern_index == 0 and self.oam.sprite_x_counters[i] == 0) {
                        const p1 = self.oam.sprite_pattern_srs1[i].get();
                        const p2 = self.oam.sprite_pattern_srs2[i].get();
                        const pattern_index = p1 | (@as(u2, p2) << 1);
                        if (pattern_index != 0) {
                            sprite_pattern_index = pattern_index;
                            sprite_attribute_index = @truncate(self.oam.sprite_attributes[i]);
                            sprite_behind = getMaskBool(u8, self.oam.sprite_attributes[i], 0x20);
                            if (i == 0 and self.oam.has_sprite_0 and bg_pattern_index != 0) {
                                self.reg.setFlag(.ppu_status, "S", true);
                            }
                        }
                    } else if (self.oam.sprite_x_counters[i] > 0) {
                        self.oam.sprite_x_counters[i] -= 1;
                        continue;
                    }
                    if (self.oam.sprite_x_counters[i] == 0) {
                        self.oam.sprite_pattern_srs1[i].feed();
                        self.oam.sprite_pattern_srs2[i].feed();
                    }
                }
            }

            const addr = blk: {
                if (bg_pattern_index == 0 and sprite_pattern_index == 0) {
                    break :blk 0x3f00;
                } else {
                    var pattern_index: u2 = undefined;
                    var attribute_index: u14 = undefined;
                    var palette_base: u14 = undefined;

                    if (sprite_pattern_index != 0 and !(sprite_behind and bg_pattern_index != 0)) {
                        pattern_index = sprite_pattern_index;
                        attribute_index = sprite_attribute_index;
                        palette_base = 0x3f10;
                    } else {
                        pattern_index = bg_pattern_index;
                        const a1 = self.attribute_sr1.get(self.fine_x);
                        const a2 = self.attribute_sr2.get(self.fine_x);
                        attribute_index = a1 | (@as(u2, a2) << 1);
                        palette_base = 0x3f00;
                    }

                    break :blk palette_base | (attribute_index << 2) | pattern_index;
                }
            };

            const palette_byte = self.mem.read(addr) & 0x3f;
            self.pixel_buffer.putPixel(self.cycle, self.scanline, common.palette[palette_byte]);
        }
    };
}

const BgPatternShiftRegister = struct {
    bits: u16 = 0,
    next_byte: u8 = 0,

    fn feed(self: *BgPatternShiftRegister) void {
        self.bits <<= 1;
    }

    fn prepare(self: *BgPatternShiftRegister, byte: u8) void {
        self.next_byte = byte;
    }

    fn load(self: *BgPatternShiftRegister) void {
        self.bits |= self.next_byte;
        self.next_byte = 0;
    }

    fn get(self: BgPatternShiftRegister, offset: u3) u1 {
        return @truncate(((self.bits << offset) & 0x8000) >> 15);
    }
};

const SpritePatternShiftRegister = struct {
    bits: u8 = 0,

    fn feed(self: *SpritePatternShiftRegister) void {
        self.bits <<= 1;
    }

    fn load(self: *SpritePatternShiftRegister, byte: u8) void {
        self.bits = byte;
    }

    fn get(self: SpritePatternShiftRegister) u1 {
        return @truncate((self.bits & 0x80) >> 7);
    }
};

const AttributeShiftRegister = struct {
    bits: u8 = 0,
    latch: u1 = 0,
    next_latch: u1 = 0,

    fn feed(self: *AttributeShiftRegister) void {
        self.bits = (self.bits << 1) | self.latch;
    }

    fn prepare(self: *AttributeShiftRegister, bit: u1) void {
        self.next_latch = bit;
    }

    fn load(self: *AttributeShiftRegister) void {
        self.latch = self.next_latch;
    }

    fn get(self: AttributeShiftRegister, offset: u3) u1 {
        return @truncate(((self.bits << offset) & 0x80) >> 7);
    }
};

pub fn Registers(comptime config: Config) type {
    return struct {
        const Self = @This();

        ppu: *Ppu(config),

        ppu_ctrl: u8 = 0,
        ppu_mask: u8 = 0,
        ppu_status: u8 = 0,
        oam_addr: u8 = 0,
        oam_data: u8 = 0,
        ppu_scroll: u8 = 0,
        ppu_addr: u8 = 0,
        ppu_data: u8 = 0,

        write_toggle: bool = false,
        io_bus: u8 = 0,
        vram_data_buffer: u8 = 0,

        const Flags = common.RegisterFlags(Self);

        fn init(ppu: *Ppu(config)) Self {
            return Self{ .ppu = ppu };
        }

        // flag functions do not have side effects even when they should
        fn getFlag(
            self: Self,
            comptime field: ?Flags.FieldEnum,
            comptime flags: []const u8,
        ) bool {
            return Flags.getFlag(field, flags, self);
        }

        fn getFlags(
            self: Self,
            comptime field: ?Flags.FieldEnum,
            comptime flags: []const u8,
        ) u8 {
            return Flags.getFlags(field, flags, self);
        }

        fn setFlag(
            self: *Self,
            comptime field: ?Flags.FieldEnum,
            comptime flags: []const u8,
            val: bool,
        ) void {
            return Flags.setFlag(field, flags, self, val);
        }

        fn setFlags(
            self: *Self,
            comptime field: ?Flags.FieldEnum,
            comptime flags: []const u8,
            val: u8,
        ) void {
            return Flags.setFlags(field, flags, self, val);
        }

        pub fn peek(self: Self, i: u3) u8 {
            return switch (i) {
                0 => self.ppu_ctrl,
                1 => self.ppu_mask,
                2 => self.ppu_status,
                3 => self.oam_addr,
                4 => self.oam_data,
                5 => self.ppu_scroll,
                6 => self.ppu_addr,
                7 => self.ppu_data,
            };
        }

        pub fn read(self: *Self, i: u3) u8 {
            switch (i) {
                0, 1, 3, 5, 6 => return self.io_bus,
                2 => {
                    const prev = self.ppu_status;
                    self.ppu.reg.setFlag(.ppu_status, "V", false);
                    self.write_toggle = false;
                    return prev | (self.io_bus & 0x1f);
                },
                4 => {
                    return self.ppu.oam.primary[self.oam_addr];
                },
                7 => {
                    const val = blk: {
                        const mem_val = self.ppu.mem.read(@truncate(self.ppu.vram_addr.value));
                        if (self.ppu.vram_addr.value < 0x3f00) {
                            const prev = self.vram_data_buffer;
                            self.vram_data_buffer = mem_val;
                            break :blk prev;
                        } else {
                            // quirk
                            const nametable_addr = @as(u14, @truncate(self.ppu.vram_addr.value)) & 0x2fff;
                            self.vram_data_buffer = self.ppu.mem.read(nametable_addr);
                            break :blk mem_val;
                        }
                    };
                    self.ppu.vram_addr.value +%= if (self.getFlag(null, "I")) @as(u8, 32) else 1;
                    return val;
                },
            }
        }

        pub fn write(self: *Self, i: u3, val: u8) void {
            self.io_bus = val;
            const val_u15: u15 = val;
            switch (i) {
                0 => {
                    setMask(u15, &self.ppu.vram_temp.value, (val_u15 & 3) << 10, 0b000_1100_0000_0000);
                    self.ppu_ctrl = val;
                },
                1 => self.ppu_mask = val,
                2 => {},
                3 => self.oam_addr = val,
                4 => {
                    self.ppu.oam.primary[self.oam_addr] = val;
                    self.oam_addr +%= 1;
                },
                5 => if (!self.write_toggle) {
                    setMask(u15, &self.ppu.vram_temp.value, val >> 3, 0x1f);
                    self.ppu.fine_x = @truncate(val);
                    self.write_toggle = true;
                } else {
                    setMask(
                        u15,
                        &self.ppu.vram_temp.value,
                        ((val_u15 & 0xf8) << 2) | ((val_u15 & 7) << 12),
                        0b111_0011_1110_0000,
                    );
                    self.write_toggle = false;
                },
                6 => if (!self.write_toggle) {
                    setMask(u15, &self.ppu.vram_temp.value, (val_u15 & 0x3f) << 8, 0b0111_1111_0000_0000);
                    self.write_toggle = true;
                } else {
                    setMask(u15, &self.ppu.vram_temp.value, val_u15, 0xff);
                    self.ppu.vram_addr.value = self.ppu.vram_temp.value;
                    self.write_toggle = false;
                },
                7 => {
                    self.ppu.mem.write(@truncate(self.ppu.vram_addr.value), val);
                    self.ppu.vram_addr.value +%= if (self.getFlag(null, "I")) @as(u8, 32) else 1;
                },
            }
        }
    };
}

pub fn Memory(comptime config: Config) type {
    return struct {
        const Self = @This();

        cart: *Cart(config),
        nametables: [0x1000]u8,
        palettes: [0x20]u8,

        address_bus: u14 = 0,

        fn init(cart: *Cart(config)) Self {
            return Self{
                .cart = cart,
                .nametables = std.mem.zeroes([0x1000]u8),
                .palettes = std.mem.zeroes([0x20]u8),
            };
        }

        pub fn peek(self: Self, addr: u14) u8 {
            return switch (addr) {
                0x0000...0x1fff => self.cart.peekChr(addr),
                0x2000...0x3eff => self.nametables[self.cart.mirrorNametable(addr)],
                0x3f00...0x3fff => if (addr & 3 == 0) self.palettes[addr & 0x0c] else self.palettes[addr & 0x1f],
            };
        }

        pub fn read(self: *Self, addr: u14) u8 {
            self.address_bus = addr;
            return switch (addr) {
                0x0000...0x1fff => self.cart.readChr(addr),
                0x2000...0x3eff => self.nametables[self.cart.mirrorNametable(addr)],
                0x3f00...0x3fff => if (addr & 3 == 0) self.palettes[addr & 0x0c] else self.palettes[addr & 0x1f],
            };
        }

        pub fn write(self: *Self, addr: u14, val: u8) void {
            self.address_bus = addr;
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

const Oam = struct {
    primary: [0x100]u8,
    secondary: [0x20]u8,

    // information needed to draw current scanline
    sprite_pattern_srs1: [8]SpritePatternShiftRegister,
    sprite_pattern_srs2: [8]SpritePatternShiftRegister,
    sprite_attributes: [8]u8,
    sprite_x_counters: [8]u8,
    active_sprites: u8,
    has_sprite_0: bool,

    // for sprite evaluation step 2
    temp_read_byte: u8,
    primary_index: u8,
    sprites_found: u8,
    search_finished: bool,
    next_has_sprite_0: bool,

    // for sprite evaluation step 3
    sprite_index: u8,

    fn resetSecondaryTemps(self: *Oam) void {
        self.primary_index = 0;
        self.sprites_found = 0;
        self.search_finished = false;
        self.active_sprites = self.sprite_index;
        self.has_sprite_0 = self.next_has_sprite_0;
        self.next_has_sprite_0 = false;
        self.sprite_index = 0;
    }

    fn readForSecondary(self: *Oam) void {
        self.temp_read_byte = self.primary[self.primary_index];
    }

    fn storeSecondary(self: *Oam) void {
        self.secondary[self.sprites_found * 4 + (self.primary_index & 3)] = self.temp_read_byte;
        self.primary_index +%= 1;
    }
};
