const std = @import("std");
const FrameBuffer = @import("../sdl.zig").FrameBuffer;

const Cart = @import("../cart.zig").Cart;
const Cpu = @import("../cpu.zig").Cpu;

const flags_ = @import("../flags.zig");
const CreateFlags = flags_.CreateFlags;
const FieldFlagsDef = flags_.FieldFlagsDef;
const FieldFlags = flags_.FieldFlags;

pub const Ppu = struct {
    cart: *Cart,
    cpu: *Cpu,
    reg: Registers,
    mem: Memory,
    oam: Oam,

    scanline: u9 = 0,
    cycle: u9 = 0,
    odd_frame: bool = false,

    // internal registers
    vram_addr: Address = .{ .value = 0 },
    vram_temp: Address = .{ .value = 0 },
    fine_x: u3 = 0,
    w: bool = false,

    current_nametable_byte: u8 = 0,

    pattern_sr1: PatternShiftRegister = PatternShiftRegister{},
    pattern_sr2: PatternShiftRegister = PatternShiftRegister{},

    attribute_sr1: AttributeShiftRegister = AttributeShiftRegister{},
    attribute_sr2: AttributeShiftRegister = AttributeShiftRegister{},

    frame_buffer: FrameBuffer,
    present_frame: bool = false,

    const Address = struct {
        value: u15,

        pub fn coarseX(self: Address) u5 {
            return @truncate(u5, self.value);
        }

        pub fn coarseY(self: Address) u5 {
            return @truncate(u5, self.value >> 5);
        }

        pub fn nametableSelect(self: Address) u2 {
            return @truncate(u2, self.value >> 10);
        }

        pub fn fineY(self: Address) u3 {
            return @truncate(u3, self.value >> 12);
        }

        pub fn fullY(self: Address) u8 {
            return (@as(u8, self.coarseY()) << 3) | self.fineY();
        }
    };

    const PatternShiftRegister = struct {
        bits: u16 = 0,
        next_byte: u8 = 0,

        pub fn clear(self: *PatternShiftRegister) void {
            self.bits = 0;
            self.next_byte = 0;
        }

        pub fn feed(self: *PatternShiftRegister) void {
            self.bits <<= 1;
        }

        pub fn prepare(self: *PatternShiftRegister, byte: u8) void {
            self.next_byte = byte;
        }

        pub fn load(self: *PatternShiftRegister) void {
            self.bits |= self.next_byte;
            self.next_byte = 0;
        }

        pub fn get(self: PatternShiftRegister, offset: u3) u1 {
            return @truncate(u1, ((self.bits << offset) & 0x8000) >> 15);
        }
    };

    const AttributeShiftRegister = struct {
        bits: u8 = 0,
        latch: u1 = 0,
        next_latch: u1 = 0,

        pub fn clear(self: *PatternShiftRegister) void {
            self.bits = 0;
            self.latch = 0;
            self.next_latch = 0;
        }

        pub fn feed(self: *AttributeShiftRegister) void {
            self.bits = (self.bits << 1) | self.latch;
        }

        pub fn prepare(self: *AttributeShiftRegister, bit: u1) void {
            self.next_latch = bit;
        }

        pub fn load(self: *AttributeShiftRegister) void {
            self.latch = self.next_latch;
        }

        pub fn get(self: AttributeShiftRegister, offset: u3) u1 {
            return @truncate(u1, ((self.bits << offset) & 0x80) >> 7);
        }
    };

    pub const Registers = packed struct {
        ppu_ctrl: u8,
        ppu_mask: u8,
        ppu_status: u8,
        oam_addr: u8,
        oam_data: u8,
        ppu_scroll: u8,
        ppu_addr: u8,
        ppu_data: u8,

        // internal registers
        // https://wiki.nesdev.com/w/index.php?title=PPU_registers
        // slightly diverges from nesdev, the last char of flags 0 and 1 are made lowercase
        const ff_masks = CreateFlags(Registers, ([_]FieldFlagsDef{
            .{ .field = "ppu_ctrl", .flags = "VPHBSINn" },
            .{ .field = "ppu_mask", .flags = "BGRsbMmg" },
            .{ .field = "ppu_status", .flags = "VSO?????" },
        })[0..]){};

        // flag functions do not have side effects even when they should
        fn getFlag(self: Registers, comptime flags: FieldFlags) bool {
            return ff_masks.getFlag(self, flags);
        }

        fn getFlags(self: Registers, comptime flags: FieldFlags) u8 {
            return ff_masks.getFlags(self, flags);
        }

        fn setFlag(self: *Registers, comptime flags: FieldFlags, val: bool) void {
            return ff_masks.setFlag(self, flags, val);
        }

        fn setFlags(self: *Registers, comptime flags: FieldFlags, val: u8) void {
            return ff_masks.setFlags(self, flags, val);
        }

        pub fn peek(self: Registers, i: u3) u8 {
            return @truncate(u8, (@bitCast(u64, self) >> (@as(u6, i) * 8)));
        }

        pub fn read(self: *Registers, i: u3) u8 {
            var ppu = @fieldParentPtr(Ppu, "reg", self);
            const val = self.peek(i);
            switch (i) {
                2 => {
                    ppu.reg.setFlag(.{ .field = "ppu_status", .flags = "V" }, false);
                    ppu.w = false;
                },
                4 => {
                    return ppu.oam.primary[self.oam_addr];
                },
                7 => {
                    var prev = self.ppu_data;
                    self.ppu_data = ppu.mem.read(@truncate(u14, ppu.vram_addr.value));
                    ppu.vram_addr.value +%= if (ppu.reg.getFlag(.{ .flags = "I" })) @as(u8, 32) else 1;
                    return prev;
                },
                else => {},
            }
            return val;
        }

        pub fn write(self: *Registers, i: u3, val: u8) void {
            var ppu = @fieldParentPtr(Ppu, "reg", self);
            var val_u15 = @as(u15, val);
            switch (i) {
                0 => {
                    const mask = ~@as(u15, 0b000_1100_0000_0000);
                    ppu.vram_temp.value = (ppu.vram_temp.value & mask) | ((val_u15 & 3) << 10);
                },
                4 => {
                    ppu.oam.primary[self.oam_addr] = val;
                },
                5 => if (!ppu.w) {
                    ppu.vram_temp.value = (ppu.vram_temp.value & ~@as(u15, 0x1f)) | (val >> 3);
                    ppu.fine_x = @truncate(u3, val);
                    ppu.w = true;
                } else {
                    const old_t = ppu.vram_temp.value & ~@as(u15, 0b111_0011_1110_0000);
                    ppu.vram_temp.value = old_t | ((val_u15 & 0xf8) << 2) | ((val_u15 & 7) << 12);
                    ppu.w = false;
                },
                6 => if (!ppu.w) {
                    const mask = ~@as(u15, 0b0111_1111_0000_0000);
                    ppu.vram_temp.value = (ppu.vram_temp.value & mask) | ((val_u15 & 0x3f) << 8);
                    ppu.w = true;
                } else {
                    const mask = ~@as(u15, 0xff);
                    ppu.vram_temp.value = (ppu.vram_temp.value & mask) | val_u15;
                    ppu.vram_addr.value = ppu.vram_temp.value;
                    ppu.w = false;
                },
                7 => {
                    ppu.mem.write(@truncate(u14, ppu.vram_addr.value), val);
                    ppu.vram_addr.value +%= if (ppu.reg.getFlag(.{ .flags = "I" })) @as(u8, 32) else 1;
                },
                else => {},
            }
            const bytes = @bitCast(u64, self.*);
            const shift = @as(u6, i) * 8;
            const mask = @as(u64, 0xff) << shift;
            self.* = @bitCast(Registers, (bytes & ~mask) | @as(u64, val) << shift);
        }
    };

    pub const Memory = struct {
        nametables: [0x1000]u8,
        palettes: [0x20]u8,

        pub const peek = read;

        pub fn read(self: Memory, addr: u14) u8 {
            return switch (addr) {
                0x0000...0x1fff => @fieldParentPtr(Ppu, "mem", &self).cart.readChr(addr),
                0x2000...0x3eff => self.nametables[addr & 0xfff],
                0x3f00...0x3fff => if (addr & 3 == 0) self.palettes[addr & 0x0c] else self.palettes[addr & 0x1f],
            };
        }

        pub fn write(self: *Memory, addr: u14, val: u8) void {
            switch (addr) {
                0x2000...0x3eff => self.nametables[addr & 0xfff] = val,
                0x3f00...0x3fff => if (addr & 3 == 0) {
                    self.palettes[addr & 0x0c] = val;
                } else {
                    self.palettes[addr & 0x1f] = val;
                },
                0x0000...0x1fff => {
                    std.log.err("Unimplemented write memory address ({x:0>4})", .{addr});
                },
            }
        }
    };

    pub const Oam = struct {
        primary: [0x100]u8,

        secondary: [0x20]u8,
        sprite_pattern_srs1: [8]PatternShiftRegister,
        sprite_pattern_srs2: [8]PatternShiftRegister,
        sprite_attributes: [8]u2,
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

        pub fn resetSecondaryTemps(self: *Oam) void {
            self.primary_index = 0;
            self.sprites_found = 0;
            self.search_finished = false;
            self.active_sprites = self.sprite_index;
            self.has_sprite_0 = self.next_has_sprite_0;
            self.next_has_sprite_0 = false;
            self.sprite_index = 0;
        }

        pub fn readForSecondary(self: *Oam) void {
            self.temp_read_byte = self.primary[self.primary_index];
        }

        pub fn storeSecondary(self: *Oam) void {
            self.secondary[self.sprites_found * 4 + (self.primary_index & 3)] = self.temp_read_byte;
            self.primary_index +%= 1;
        }
    };

    pub fn init(cart: *Cart, cpu: *Cpu, frame_buffer: FrameBuffer) Ppu {
        return Ppu{
            .cart = cart,
            .cpu = cpu,
            .reg = std.mem.zeroes(Registers),
            .mem = std.mem.zeroes(Memory),
            .oam = std.mem.zeroes(Oam),
            .frame_buffer = frame_buffer,
        };
    }

    pub fn deinit(self: Ppu) void {
        _ = self;
    }

    fn incCoarseX(self: *Ppu) void {
        if ((self.vram_addr.value & @as(u15, 0x1f)) == 0x1f) {
            self.vram_addr.value = (self.vram_addr.value & ~@as(u15, 0x1f)) ^ 0x400;
        } else {
            self.vram_addr.value +%= 1;
        }
    }

    fn incCoarseY(self: *Ppu) void {
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
            self.vram_addr.value = (self.vram_addr.value & ~@as(u15, 0x03e0)) | (y << 5);
        }
    }

    fn renderingEnabled(self: Ppu) bool {
        return self.reg.getFlags(.{ .flags = "sb" }) != 0;
    }

    fn onRenderScanline(self: Ppu) bool {
        return self.scanline < 240 or self.scanline == 261;
    }

    fn feedShiftRegisters(self: *Ppu) void {
        self.pattern_sr1.feed();
        self.pattern_sr2.feed();
        self.attribute_sr1.feed();
        self.attribute_sr2.feed();
    }

    fn loadShiftRegisters(self: *Ppu) void {
        self.pattern_sr1.load();
        self.pattern_sr2.load();
        self.attribute_sr1.load();
        self.attribute_sr2.load();
    }

    fn fetchNametableByte(self: *Ppu) void {
        self.current_nametable_byte = self.mem.read(0x2000 | @truncate(u14, self.vram_addr.value & 0xfff));
    }

    fn fetchAttributeByte(self: *Ppu) void {
        const attribute_table_byte: u8 = self.mem.read(@as(u14, 0x23c0) |
            self.vram_addr.nametableSelect() |
            ((@as(u14, self.vram_addr.coarseY()) << 1) & 0x38) |
            ((self.vram_addr.coarseX() >> 2) & 7));

        const x_quadrant = self.vram_addr.value & 2;
        const y_quadrant = (self.vram_addr.value >> 4) & 4;
        const shift = @truncate(u3, x_quadrant | y_quadrant);
        self.attribute_sr1.prepare(@truncate(u1, attribute_table_byte >> shift));
        self.attribute_sr2.prepare(@truncate(u1, attribute_table_byte >> (shift + 1)));
    }

    fn fetchLowBgTile(self: *Ppu) void {
        const addr = (@as(u14, self.current_nametable_byte) << 4) | self.vram_addr.fineY();
        const offset = if (self.reg.getFlag(.{ .field = "ppu_ctrl", .flags = "B" })) @as(u14, 0x1000) else 0;
        const pattern_table_byte = self.mem.read(addr | offset);
        self.pattern_sr1.prepare(pattern_table_byte);
    }

    fn fetchHighBgTile(self: *Ppu) void {
        const addr = (@as(u14, self.current_nametable_byte) << 4) | self.vram_addr.fineY();
        const offset = if (self.reg.getFlag(.{ .field = "ppu_ctrl", .flags = "B" })) @as(u14, 0x1000) else 0;
        const pattern_table_byte = self.mem.read(addr | offset | 8);
        self.pattern_sr2.prepare(pattern_table_byte);
    }

    fn fetchNextByte(self: *Ppu) void {
        if (!((self.cycle >= 1 and self.cycle <= 256) or (self.cycle >= 321 and self.cycle <= 336))) {
            return;
        }

        self.feedShiftRegisters();

        switch (@truncate(u2, self.cycle >> 1)) {
            0 => {
                self.loadShiftRegisters();
                self.fetchNametableByte(); // cycle % 8 == 0
            },
            1 => self.fetchAttributeByte(), // cycle % 8 == 2
            2 => self.fetchLowBgTile(), // cycle % 8 == 4
            3 => self.fetchHighBgTile(), // cycle % 8 == 6
        }
    }

    fn spriteEvaluation(self: *Ppu) void {
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
                    // check if y is in range
                    const sprite_y = self.oam.temp_read_byte;
                    if (sprite_y <= self.scanline and @as(u9, sprite_y) + 8 > self.scanline) {
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
                if (self.cycle & 1 != 0 or self.oam.sprite_index == self.oam.sprites_found or self.oam.sprite_index == 8) {
                    return;
                }
                const y = self.oam.secondary[self.oam.sprite_index * 4];
                const tile_index = self.oam.secondary[self.oam.sprite_index * 4 + 1];
                const attributes = self.oam.secondary[self.oam.sprite_index * 4 + 2];
                const x = self.oam.secondary[self.oam.sprite_index * 4 + 3];
                const y_offset = @truncate(u3, self.vram_addr.fineY() -% y -% 1);
                _ = y;
                const pattern_offset = if (self.reg.getFlag(.{ .field = "ppu_ctrl", .flags = "S" }))
                    @as(u14, 0x1000)
                else
                    0;
                switch (@truncate(u2, self.cycle >> 1)) {
                    0 => {},
                    1 => {
                        self.oam.sprite_x_counters[self.oam.sprite_index] = x;
                        self.oam.sprite_attributes[self.oam.sprite_index] = @truncate(u2, attributes);
                    },
                    2 => {
                        const pattern_byte = blk: {
                            var byte = self.mem.read(pattern_offset | (@as(u14, tile_index) << 4) | y_offset);
                            if (attributes & 0x40 != 0) {
                                byte = @bitReverse(u8, byte);
                            }
                            break :blk byte;
                        };
                        // TODO
                        self.oam.sprite_pattern_srs1[self.oam.sprite_index].clear();
                        self.oam.sprite_pattern_srs1[self.oam.sprite_index].bits = @as(u16, pattern_byte) << 8;
                    },
                    3 => {
                        const pattern_byte = blk: {
                            var byte = self.mem.read(pattern_offset | (@as(u14, tile_index) << 4) | y_offset | 8);
                            if (attributes & 0x40 != 0) {
                                byte = @bitReverse(u8, byte);
                            }
                            break :blk byte;
                        };
                        self.oam.sprite_pattern_srs2[self.oam.sprite_index].clear();
                        self.oam.sprite_pattern_srs2[self.oam.sprite_index].bits = @as(u16, pattern_byte) << 8;
                        self.oam.sprite_index += 1;
                    },
                }
            },
            else => {},
        }
    }

    pub fn runCycle(self: *Ppu) void {
        if (!self.onRenderScanline()) {
            self.runPostCycle();
            return;
        }

        if (self.scanline == 261 and self.cycle == 339 and self.odd_frame) {
            self.cycle += 1;
        }
        self.fetchNextByte();
        if (self.scanline != 261) {
            self.spriteEvaluation();
        }

        if (self.renderingEnabled() and self.scanline < 240 and self.cycle < 256) {
            self.drawPixel();
        }

        if (self.renderingEnabled() and self.cycle > 0) {
            if (self.cycle > 257 and self.cycle < 321) {
                self.reg.oam_addr = 0;

                if (self.scanline == 261 and self.cycle >= 280 and self.cycle <= 304) {
                    // set coarse and fine y as well as 0x800 (high nametable select bit)
                    const mask = @as(u15, 0x7be0);
                    self.vram_addr.value = (self.vram_addr.value & ~mask) | (self.vram_temp.value & mask);
                }
            } else if (self.cycle == 256) {
                self.incCoarseY();
            } else if ((self.cycle & 7) == 0) {
                self.incCoarseX();
            } else if (self.cycle == 257) {
                // set coarse x and 0x400 (low nametable select bit)
                const mask = @as(u15, 0x41f);
                self.vram_addr.value = (self.vram_addr.value & ~mask) | (self.vram_temp.value & mask);
            }
        }
        self.runPostCycle();
    }

    fn runPostCycle(self: *Ppu) void {
        self.cycle += 1;
        if (self.cycle == 341) {
            self.cycle = 0;
            self.scanline = (self.scanline + 1) % 262;
            self.oam.resetSecondaryTemps();
        }

        if (self.scanline == 241 and self.cycle == 1) {
            self.reg.setFlag(.{ .field = "ppu_status", .flags = "V" }, true);
            if (self.reg.getFlag(.{ .field = "ppu_ctrl", .flags = "V" })) {
                self.cpu.nmi();
            }
            self.present_frame = true;
        } else if (self.scanline == 261 and self.cycle == 1) {
            self.reg.setFlags(.{ .field = "ppu_status", .flags = "VS" }, 0);
            self.odd_frame = !self.odd_frame;
        }
    }

    fn drawPixel(self: *Ppu) void {
        const bg_pattern_index: u2 = blk: {
            const p1 = self.pattern_sr1.get(self.fine_x);
            const p2 = self.pattern_sr2.get(self.fine_x);
            break :blk p1 | (@as(u2, p2) << 1);
        };

        var sprite_0 = false;
        var sprite_pattern_index: u2 = 0;
        var sprite_attribute_index: u2 = 0;
        {
            var i: usize = 0;
            while (i < self.oam.active_sprites) : (i += 1) {
                if (sprite_pattern_index == 0 and self.oam.sprite_x_counters[i] == 0) {
                    const p1 = self.oam.sprite_pattern_srs1[i].get(0);
                    const p2 = self.oam.sprite_pattern_srs2[i].get(0);
                    const pattern_index = p1 | (@as(u2, p2) << 1);
                    if (pattern_index != 0) {
                        sprite_pattern_index = pattern_index;
                        sprite_attribute_index = self.oam.sprite_attributes[i];
                        if (i == 0 and self.oam.has_sprite_0) {
                            sprite_0 = true;
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

        var pattern_index: u2 = undefined;
        var attribute_index: u14 = undefined;
        var palette_base: u14 = undefined;
        if (sprite_pattern_index != 0) {
            pattern_index = sprite_pattern_index;
            attribute_index = sprite_attribute_index;
            palette_base = 0x3f10;

            if (bg_pattern_index != 0) {
                self.reg.setFlag(.{ .field = "ppu_status", .flags = "S" }, true);
            }
        } else {
            pattern_index = bg_pattern_index;
            const a1 = self.attribute_sr1.get(self.fine_x);
            const a2 = self.attribute_sr2.get(self.fine_x);
            attribute_index = a1 | (@as(u2, a2) << 1);
            palette_base = 0x3f00;
        }

        const palette_index = (attribute_index << 2) | pattern_index;
        const palette_byte = self.mem.read(palette_base | palette_index);
        self.frame_buffer.putPixel(self.cycle, self.scanline, palette[palette_byte]);
    }
};

const palette = [_]u32{
    0x00666666,
    0x00002a88,
    0x001412a7,
    0x003b00a4,
    0x005c007e,
    0x006e0040,
    0x006c0600,
    0x00561d00,
    0x00333500,
    0x000b4800,
    0x00005200,
    0x00004f08,
    0x0000404d,
    0x00000000,
    0x00000000,
    0x00000000,
    0x00adadad,
    0x00155fd9,
    0x004240ff,
    0x007527fe,
    0x00a01acc,
    0x00b71e7b,
    0x00b53120,
    0x00994e00,
    0x006b6d00,
    0x00388700,
    0x000c9300,
    0x00008f32,
    0x00007c8d,
    0x00000000,
    0x00000000,
    0x00000000,
    0x00fffeff,
    0x0064b0ff,
    0x009290ff,
    0x00c676ff,
    0x00f36aff,
    0x00fe6ecc,
    0x00fe8170,
    0x00ea9e22,
    0x00bcbe00,
    0x0088d800,
    0x005ce430,
    0x0045e082,
    0x0048cdde,
    0x004f4f4f,
    0x00000000,
    0x00000000,
    0x00fffeff,
    0x00c0dfff,
    0x00d3d2ff,
    0x00e8c8ff,
    0x00fbc2ff,
    0x00fec4ea,
    0x00feccc5,
    0x00f7d8a5,
    0x00e4e594,
    0x00cfef96,
    0x00bdf4ab,
    0x00b3f3cc,
    0x00b5ebf2,
    0x00b8b8b8,
    0x00000000,
    0x00000000,
};
