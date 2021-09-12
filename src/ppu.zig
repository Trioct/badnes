const std = @import("std");
const FrameBuffer = @import("sdl.zig").FrameBuffer;

const Cart = @import("cart.zig").Cart;
const Cpu = @import("cpu.zig").Cpu;

const flags_ = @import("flags.zig");
const CreateFlags = flags_.CreateFlags;
const FieldFlagsDef = flags_.FieldFlagsDef;
const FieldFlags = flags_.FieldFlags;

pub const Ppu = struct {
    cart: *Cart,
    cpu: *Cpu,
    reg: Registers,
    mem: Memory,

    scanline: u9 = 0,
    cycle: u9 = 0,
    odd_frame: bool = false,

    // internal registers
    v: Address = .{ .value = 0 },
    t: Address = .{ .value = 0 },
    x: u3 = 0,
    w: bool = false,

    frame_buffer: FrameBuffer,
    present_frame: bool = false,

    const Address = struct {
        value: u15,

        pub fn coarseX(self: Address) u5 {
            return @intCast(u5, self.value & 0x1f);
        }

        pub fn coarseY(self: Address) u5 {
            return @intCast(u5, (self.value >> 5) & 0x1f);
        }

        pub fn nametableSelect(self: Address) u2 {
            return @intCast(u2, (self.value >> 10) & 3);
        }

        pub fn fineY(self: Address) u3 {
            return @intCast(u3, (self.value >> 12) & 7);
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
            return @intCast(u8, (@bitCast(u64, self) >> (@as(u6, i) * 8)) & 0xff);
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
                    return ppu.mem.oam[self.oam_addr];
                },
                7 => {
                    self.ppu_data = ppu.mem.read(@intCast(u14, ppu.v.value & 0x3fff));
                    return self.ppu_data;
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
                    ppu.t.value = (ppu.t.value & mask) | ((val_u15 & 3) << 10);
                },
                4 => {
                    ppu.mem.oam[self.oam_addr] = val;
                },
                5 => if (!ppu.w) {
                    ppu.t.value = (ppu.t.value & ~@as(u15, 0x1f)) | (val >> 3);
                    ppu.x = @intCast(u3, val & 7);
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
                    ppu.mem.write(@intCast(u14, ppu.v.value & 0x3fff), val);
                    ppu.v.value +%= if (ppu.reg.getFlag(.{ .flags = "I" })) @as(u8, 32) else 1;
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
        oam: [0x100]u8,

        pub const peek = read;

        pub fn read(self: Memory, addr: u14) u8 {
            return switch (addr) {
                0x0000...0x1fff => @fieldParentPtr(Ppu, "mem", &self).cart.readChr(addr),
                0x2000...0x3eff => self.nametables[addr & 0xfff],
                0x3f00...0x3fff => if (addr & 3 == 0) self.palettes[0] else self.palettes[addr & 0x1f],
            };
        }

        pub fn write(self: *Memory, addr: u14, val: u8) void {
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

    pub fn init(cart: *Cart, cpu: *Cpu, frame_buffer: FrameBuffer) Ppu {
        return Ppu{
            .cart = cart,
            .cpu = cpu,
            .reg = std.mem.zeroes(Registers),
            .mem = std.mem.zeroes(Memory),
            .frame_buffer = frame_buffer,
        };
    }

    pub fn deinit(self: Ppu) void {
        _ = self;
    }

    pub fn incCoarseX(self: *Ppu) void {
        if ((self.v.value & @as(u15, 0x1f)) == 0x1f) {
            self.v.value = (self.v.value & ~@as(u15, 0x1f)) ^ 0x400;
        } else {
            self.v.value +%= 1;
        }
    }

    pub fn incCoarseY(self: *Ppu) void {
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

    pub fn renderingEnabled(self: Ppu) bool {
        return self.reg.getFlags(.{ .flags = "sb" }) != 0;
    }

    pub fn runCycle(self: *Ppu) void {
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
                self.cpu.nmi();
            }
            self.present_frame = true;
        } else if (self.scanline == 261 and self.cycle == 1) {
            self.reg.setFlags(.{ .field = "ppu_status", .flags = "VS" }, 0);
            self.odd_frame = !self.odd_frame;
        }
    }

    pub fn runVisibleScanlineCycle(self: *Ppu) void {
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

    fn drawPixel(self: *Ppu) void {
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
            const nametable_byte: u14 = self.mem.peek(0x2000 | @intCast(u14, reverted_v.value & 0xfff));
            const addr = (nametable_byte << 4) | reverted_v.fineY();
            const offset = if (self.reg.getFlag(.{ .field = "ppu_ctrl", .flags = "B" })) @as(u14, 0x1000) else 0;
            const pattern_table_byte1 = self.mem.peek(addr | offset);
            const pattern_table_byte2 = self.mem.peek(addr | 8 | offset);
            const pattern_table_bit1: u1 = @intCast(u1, (pattern_table_byte1 >> (7 - @intCast(u3, self.cycle & 7))) & 1);
            const pattern_table_bit2: u1 = @intCast(u1, (pattern_table_byte2 >> (7 - @intCast(u3, self.cycle & 7))) & 1);
            break :blk pattern_table_bit1 | (@as(u2, pattern_table_bit2) << 1);
        };

        const x = self.cycle;
        const y = (@as(u8, reverted_v.coarseY()) << 3) | reverted_v.fineY();
        for (@ptrCast([*]u32, @alignCast(4, self.mem.oam[0..]))[0..64]) |cell| {
            const cell_x = @intCast(u8, cell >> 24);
            const cell_y = @intCast(u8, cell & 0xff);
            if (cell_x < x and cell_x >= x -% 8 and cell_y <= y and cell_y > y -% 8) {
                const tile_index = @intCast(u14, (cell >> 8) & 0xff);
                const attributes = @intCast(u8, (cell >> 16) & 0xff);

                const addr = (tile_index << 4) | @intCast(u3, (y - cell_y) & 7);
                const offset = if (self.reg.getFlag(.{ .field = "ppu_ctrl", .flags = "S" })) @as(u14, 0x1000) else 0;
                const pattern_table_byte1 = self.mem.peek(addr | offset);
                const pattern_table_byte2 = self.mem.peek(addr | 8 | offset);
                const shift = blk: {
                    if (attributes >> 6 == 0) {
                        break :blk @intCast(u3, cell_x & 7) -% @intCast(u3, self.cycle & 7);
                    } else {
                        break :blk @intCast(u3, self.cycle & 7) -% @intCast(u3, cell_x & 7) -% 1;
                    }
                };
                const pattern_table_bit1: u1 = @intCast(u1, (pattern_table_byte1 >> shift) & 1);
                const pattern_table_bit2: u1 = @intCast(u1, (pattern_table_byte2 >> shift) & 1);
                const sprite_attribute_table_index: u2 = pattern_table_bit1 | (@as(u2, pattern_table_bit2) << 1);
                if (sprite_attribute_table_index == 0) {
                    continue;
                } else if (bg_attribute_table_index != 0) {
                    self.reg.setFlag(.{ .field = "ppu_status", .flags = "S" }, true);
                }

                const palette_index = @as(u14, ((attributes & 3) << 2) | sprite_attribute_table_index);
                const palette_byte = self.mem.peek(0x3f10 | palette_index);

                self.frame_buffer.putPixel(self.cycle, self.scanline, palette[palette_byte]);
                return;
            }
        }

        const attribute_table_byte: u8 = self.mem.peek(@intCast(u14, 0x23c0 |
            (reverted_v.value & 0x0c00) |
            ((reverted_v.value >> 4) & 0x38) |
            ((reverted_v.value >> 2) & 7)));

        const palette_index = @as(u14, ((attribute_table_byte & 3) << 2) | bg_attribute_table_index);
        const palette_byte = self.mem.peek(0x3f00 | palette_index);

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
