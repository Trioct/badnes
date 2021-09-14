const std = @import("std");
const audio = @import("sdl/audio.zig");
const AudioContext = audio.AudioContext;

const Cpu = @import("cpu.zig").Cpu;
const flags = @import("flags.zig");

const cpu_freq = 1789773;
const frame_counter_rate = 1 / 240.0;

const triangle_duty_values = [_]u8{
    15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5,  4,  3,  2,  1,  0,
    0,  1,  2,  3,  4,  5,  6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
};

pub const Apu = struct {
    reg: Registers,

    cycles: usize = 0,
    frame_counter: usize = 0,
    audio_context: *AudioContext,

    pub const Registers = struct {
        triangle: TriangleChannel,

        pub const Timer = struct {
            value: u11,
            reload_value: u11,
        };

        pub const TriangleChannel = struct {
            linear_counter: LinearCounter,
            timer: Timer,
            length_counter: u5,
            control_flag: bool,

            duty_value: u5,

            pub const LinearCounter = struct {
                value: u7,
                reload_value: u7,
                reload: bool,
            };

            pub fn stepCounter(self: *TriangleChannel) void {
                if (self.linear_counter.reload) {
                    self.linear_counter.value = self.linear_counter.reload_value;
                    //std.debug.print("{}\n", .{self.linear_counter.value});
                } else if (self.linear_counter.value > 0) {
                    self.linear_counter.value -= 1;
                }
                // if (!self.control_flag) {
                //     self.linear_counter.reload = false;
                // }
            }
        };
    };

    pub fn init(audio_context: *AudioContext) Apu {
        return Apu{
            .reg = std.mem.zeroes(Registers),

            .audio_context = audio_context,
        };
    }

    pub fn read(self: Apu, addr: u16) u8 {
        _ = self;
        return switch (addr) {
            0x4015 => 0,
            else => 0,
        };
    }

    pub fn write(self: *Apu, addr: u16, val: u8) void {
        switch (addr) {
            0x08 => {
                self.reg.triangle.control_flag = flags.getMaskBool(u11, val, 0x80);
                //std.debug.print("{x:0>2} {x:0>2}\n", .{ self.reg.triangle.control_flag, val });
                self.reg.triangle.linear_counter.reload_value = @truncate(u7, val);
            },
            0x0a => {
                flags.setMask(u11, &self.reg.triangle.timer.reload_value, val, 0xff);
            },
            0x0b => {
                self.reg.triangle.linear_counter.reload = true;
                self.reg.triangle.length_counter = @truncate(u5, val >> 3);
                flags.setMask(u11, &self.reg.triangle.timer.reload_value, @as(u11, val) << 8, 0x700);
            },
            else => {},
        }
    }

    pub fn runCycle(self: *Apu) void {
        const pre_cycle_time = @intToFloat(f64, self.cycles) / cpu_freq;
        self.cycles +%= 1;
        const post_cycle_time = @intToFloat(f64, self.cycles) / cpu_freq;

        if (self.reg.triangle.timer.value == 0) {
            self.reg.triangle.timer.value = self.reg.triangle.timer.reload_value;
            if (self.reg.triangle.length_counter > 0 and self.reg.triangle.linear_counter.value > 0) {
                self.reg.triangle.duty_value +%= 1;
            }
        } else {
            self.reg.triangle.timer.value -= 1;
        }

        // checks if it crossed a whole number threshold
        const f1 = @floatToInt(usize, pre_cycle_time / frame_counter_rate);
        const f2 = @floatToInt(usize, post_cycle_time / frame_counter_rate);
        if (f1 != f2) {
            switch (@truncate(u2, self.frame_counter)) {
                0 | 1 | 2 | 3 => {
                    self.reg.triangle.stepCounter();
                },
                else => {},
            }
            self.frame_counter +%= 1;
        }

        const s1 = @floatToInt(usize, pre_cycle_time * audio.sample_rate);
        const s2 = @floatToInt(usize, post_cycle_time * audio.sample_rate);
        if (s1 != s2) {
            if (self.reg.triangle.linear_counter.value != 0 and self.reg.triangle.length_counter != 0) {
                self.audio_context.addSample(triangle_duty_values[self.reg.triangle.duty_value] << 2) catch {
                    std.log.err("Couldn't add sample", .{});
                };
            } else {
                self.audio_context.addSample(0) catch {
                    std.log.err("Couldn't add sample", .{});
                };
            }
        }
    }
};
