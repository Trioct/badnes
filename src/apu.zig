const std = @import("std");
const audio = @import("audio.zig");

const console_ = @import("console.zig");
const Config = console_.Config;
const Console = console_.Console;

const Cpu = @import("cpu.zig").Cpu;
const flags = @import("flags.zig");

const cpu_freq = 1789773;
const frame_counter_rate = 1 / 240.0;

const length_counter_table = [_]u8{
    10, 254, 20, 2,  40, 4,  80, 6,  160, 8,  60, 10, 14, 12, 26, 14,
    12, 16,  24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30,
};

const pulse_duty_values = [4][8]u1{
    [8]u1{ 0, 1, 0, 0, 0, 0, 0, 0 },
    [8]u1{ 0, 1, 1, 0, 0, 0, 0, 0 },
    [8]u1{ 0, 1, 1, 1, 1, 0, 0, 0 },
    [8]u1{ 1, 0, 0, 1, 1, 1, 1, 1 },
};

const triangle_duty_values = [_]u4{
    15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5,  4,  3,  2,  1,  0,
    0,  1,  2,  3,  4,  5,  6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
};

pub fn Apu(comptime config: Config) type {
    return struct {
        const Self = @This();

        cpu: *Cpu(config),
        reg: Registers,

        cycles: usize = 0,
        frame_counter: usize = 0,
        audio_context: *audio.Context(config.method),

        next_frame_counter_timer: CycleTimer = CycleTimer.set(0),
        next_output_timer: CycleTimer = CycleTimer.set(0),

        const CycleTimer = struct {
            whole: usize,
            frac: f32,

            fn init() CycleTimer {
                return CycleTimer.set(0);
            }

            fn set(cycle: usize) CycleTimer {
                return CycleTimer{
                    .whole = cycle,
                    .frac = 0,
                };
            }

            fn setNext(self: *CycleTimer, offset: f32) void {
                self.frac += offset;

                const mod = std.math.modf(self.frac);
                self.frac -= mod.ipart;
                self.whole += @floatToInt(usize, mod.ipart);
            }

            fn isDone(self: CycleTimer, cycle: usize) bool {
                return self.whole == cycle;
            }
        };

        pub const Registers = struct {
            pulse1: PulseChannel,
            pulse2: PulseChannel,
            triangle: TriangleChannel,
            noise: NoiseChannel,

            frame_counter_mode: u1 = 0,
            irq_inhibit: bool = false,

            fn init() Registers {
                return Registers{
                    .pulse1 = PulseChannel.init(0),
                    .pulse2 = PulseChannel.init(1),
                    .triangle = std.mem.zeroes(TriangleChannel),
                    .noise = NoiseChannel{},
                };
            }
        };

        pub fn init(console: *Console(config), audio_context: *audio.Context(config.method)) Self {
            return Self{
                .cpu = &console.cpu,

                .reg = Registers.init(),
                .audio_context = audio_context,
            };
        }

        pub fn read(self: *Self, addr: u5) u8 {
            const reg = &self.reg;
            switch (addr) {
                0x15 => {
                    var val: u8 = 0;
                    val |= @as(u7, @boolToInt(reg.irq_inhibit)) << 6;
                    val |= @as(u4, @boolToInt(reg.noise.length_counter.value > 0)) << 3;
                    val |= @as(u3, @boolToInt(reg.triangle.length_counter.value > 0)) << 2;
                    val |= @as(u2, @boolToInt(reg.pulse2.length_counter.value > 0)) << 1;
                    val |= @boolToInt(reg.pulse1.length_counter.value > 0);

                    reg.irq_inhibit = false;

                    return val;
                },
                else => return 0,
            }
        }

        pub fn write(self: *Self, addr: u5, val: u8) void {
            // TODO: probably move these into functions in the registers
            const reg = &self.reg;
            switch (addr) {
                // pulse
                0x00...0x03 => reg.pulse1.write(@truncate(u2, addr), val),
                0x04...0x07 => reg.pulse2.write(@truncate(u2, addr), val),

                // triangle
                0x08 => {
                    reg.triangle.length_counter.halt = flags.getMaskBool(u8, val, 0x80);
                    reg.triangle.linear_counter.period = @truncate(u7, val);
                },
                0x0a => {
                    flags.setMask(u11, &reg.triangle.timer.period, val, 0xff);
                },
                0x0b => {
                    reg.triangle.linear_counter.reload = true;
                    reg.triangle.length_counter.setValue(length_counter_table[val >> 3]);
                    flags.setMask(u11, &reg.triangle.timer.period, @as(u11, val) << 8, 0x700);
                },

                // noise
                0x0c => {
                    reg.noise.length_counter.halt = flags.getMaskBool(u8, val, 0x20);
                    reg.noise.envelope.constant_volume = flags.getMaskBool(u8, val, 0x10);
                    reg.noise.envelope.divider_period = @truncate(u4, val);
                },
                0x0e => {
                    reg.noise.mode = flags.getMaskBool(u8, val, 0x80);
                    const period_table = [_]u13{
                        4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068,
                    };
                    reg.noise.timer.period = period_table[@truncate(u4, val)];
                },
                0x0f => {
                    reg.noise.length_counter.setValue(length_counter_table[val >> 3]);
                    reg.noise.envelope.start = true;
                },

                0x15 => {
                    _ = flags.getMaskBool(u8, val, 0x10); // DMC enable
                    reg.noise.length_counter.setEnabled(flags.getMaskBool(u8, val, 0x08));
                    reg.triangle.length_counter.setEnabled(flags.getMaskBool(u8, val, 0x04));
                    reg.pulse2.length_counter.setEnabled(flags.getMaskBool(u8, val, 0x02));
                    reg.pulse1.length_counter.setEnabled(flags.getMaskBool(u8, val, 0x01));
                },
                0x17 => {
                    reg.frame_counter_mode = @truncate(u1, val >> 7);
                    reg.irq_inhibit = flags.getMaskBool(u8, val, 0x40);
                },
                else => {},
            }
        }

        fn stepQuarterFrame(self: *Self) void {
            self.reg.pulse1.stepEnvelope();
            self.reg.pulse2.stepEnvelope();
            self.reg.triangle.stepLinear();
            self.reg.noise.stepEnvelope();
        }

        fn stepHalfFrame(self: *Self) void {
            _ = self.reg.pulse1.length_counter.step();
            _ = self.reg.pulse2.length_counter.step();
            _ = self.reg.triangle.length_counter.step();
            _ = self.reg.noise.length_counter.step();

            self.reg.pulse1.stepSweep();
            self.reg.pulse2.stepSweep();
        }

        fn getOutput(self: *Self) f32 {
            const p1_out = @intToFloat(f32, self.reg.pulse1.output());
            const p2_out = @intToFloat(f32, self.reg.pulse2.output());
            const pulse_out = 0.00752 * (p1_out + p2_out);

            const tri_out = @intToFloat(f32, self.reg.triangle.output());
            const noise_out = @intToFloat(f32, self.reg.noise.output());

            const tnd_out = 0.00851 * tri_out + 0.00494 * noise_out;
            return pulse_out + tnd_out;
        }

        pub fn runCycle(self: *Self) void {
            self.reg.triangle.stepTimer();
            if (self.cycles & 1 == 1) {
                self.reg.pulse1.stepTimer();
                self.reg.pulse2.stepTimer();
                self.reg.noise.stepTimer();
            }

            if (self.next_frame_counter_timer.isDone(self.cycles)) {
                if (self.reg.frame_counter_mode == 0) {
                    switch (@truncate(u2, self.frame_counter)) {
                        0, 2 => {
                            self.stepQuarterFrame();
                        },
                        1 => {
                            self.stepQuarterFrame();
                            self.stepHalfFrame();
                        },
                        3 => {
                            self.stepQuarterFrame();
                            self.stepHalfFrame();
                            if (!self.reg.irq_inhibit) {
                                self.cpu.irq();
                            }
                        },
                    }
                } else {
                    switch (self.frame_counter % 5) {
                        0, 2 => {
                            self.stepQuarterFrame();
                        },
                        1 => {
                            self.stepQuarterFrame();
                            self.stepHalfFrame();
                        },
                        3 => {},
                        4 => {
                            self.stepQuarterFrame();
                            self.stepHalfFrame();
                        },
                        else => unreachable,
                    }
                }
                self.frame_counter +%= 1;
                self.next_frame_counter_timer.setNext(@intToFloat(f32, cpu_freq) * frame_counter_rate);
            }

            if (self.next_output_timer.isDone(self.cycles)) {
                self.audio_context.addSample(self.getOutput()) catch {
                    std.log.err("Couldn't add sample", .{});
                };
                const freq_f = @intToFloat(f32, cpu_freq);
                const sample_f = @intToFloat(f32, audio.Context(config.method).sample_rate);
                self.next_output_timer.setNext(freq_f / sample_f);
            }

            self.cycles +%= 1;
        }
    };
}

fn Timer(comptime T: type) type {
    return struct {
        value: T = 0,
        period: T = 0,

        fn reset(self: *Timer(T)) void {
            self.value = self.period;
        }
    };
}

const LengthCounter = struct {
    enabled: bool = false,
    halt: bool = false,
    value: u8 = 0,

    fn setEnabled(self: *LengthCounter, enabled: bool) void {
        self.enabled = enabled;
        if (!enabled) {
            self.value = 0;
        }
    }

    fn setValue(self: *LengthCounter, val: u8) void {
        if (self.enabled) {
            self.value = val;
        }
    }

    fn gate(self: LengthCounter) bool {
        return self.value != 0;
    }

    fn step(self: *LengthCounter) bool {
        const condition = self.enabled and !self.halt and self.value != 0;
        if (condition) {
            self.value -= 1;
        }
        return condition;
    }
};

const Envelope = struct {
    start: bool = false,
    constant_volume: bool = false,

    divider_counter: u5 = 0,
    divider_period: u4 = 0,
    decay_level_counter: u4 = 0,

    fn step(self: *Envelope, loop: bool) void {
        if (self.start) {
            self.start = false;
            self.decay_level_counter = 15;
            self.divider_counter = self.divider_period;
            return;
        }

        if (self.divider_counter == 0) {
            self.divider_counter = self.divider_period;
        } else {
            self.divider_counter -= 1;
            return;
        }

        if (self.decay_level_counter != 0) {
            self.decay_level_counter -= 1;
            return;
        }

        if (loop) {
            self.decay_level_counter = 15;
        }
    }

    fn output(self: Envelope) u4 {
        if (self.constant_volume) {
            return self.divider_period;
        } else {
            return self.decay_level_counter;
        }
    }
};

const PulseChannel = struct {
    duty_table: u2 = 0,
    duty_index: u3 = 0,

    timer: Timer(u11) = Timer(u11){},
    length_counter: LengthCounter = LengthCounter{},

    sweep: Sweep,
    envelope: Envelope = Envelope{},

    // maybe put timer in sweep?
    const Sweep = struct {
        channel: u1,

        enabled: bool = false,
        negate: bool = false,
        reload: bool = false,
        divider_counter: u4 = 0,
        divider_period: u3 = 0,
        shift_count: u3 = 0,

        target_period: u12 = 0,

        fn isMuting(self: Sweep, timer: Timer(u11)) bool {
            return timer.period < 8 or flags.getMaskBool(u12, self.target_period, 0x800);
        }

        fn step(self: *Sweep, timer: *Timer(u11)) void {
            var delta: u12 = timer.period >> self.shift_count;
            if (self.negate) {
                delta = ~delta;
                if (self.channel == 1) {
                    delta +%= 1;
                }
            }

            self.target_period = @as(u12, timer.period) +% delta;
            if (self.divider_counter == 0 and self.enabled and !self.isMuting(timer.*) and self.shift_count != 0) {
                timer.period = @truncate(u11, self.target_period);
            }
            if (self.divider_counter == 0 or self.reload) {
                self.divider_counter = self.divider_period;
                self.reload = false;
            } else {
                self.divider_counter -= 1;
            }
        }
    };

    fn init(channel: u1) PulseChannel {
        return PulseChannel{
            .sweep = Sweep{
                .channel = channel,
            },
        };
    }

    fn write(self: *PulseChannel, addr: u2, val: u8) void {
        switch (addr) {
            0x00 => {
                self.duty_table = @truncate(u2, val >> 6);
                self.length_counter.halt = flags.getMaskBool(u8, val, 0x20);
                self.envelope.constant_volume = flags.getMaskBool(u8, val, 0x10);
                self.envelope.divider_period = @truncate(u4, val);
            },
            0x01 => {
                self.sweep.enabled = (val & 0x80) != 0;
                self.sweep.negate = (val & 0x08) != 0;
                self.sweep.reload = true;
                self.sweep.divider_period = @truncate(u3, val >> 4);
                self.sweep.shift_count = @truncate(u3, val);
            },
            0x02 => {
                flags.setMask(u11, &self.timer.period, val, 0xff);
            },
            0x03 => {
                self.length_counter.setValue(length_counter_table[val >> 3]);
                flags.setMask(u11, &self.timer.period, @as(u11, val) << 8, 0x700);
                self.duty_index = 0;
                self.envelope.start = true;
            },
        }
    }

    fn stepTimer(self: *PulseChannel) void {
        if (self.timer.value == 0) {
            self.timer.reset();
            self.duty_index -%= 1;
        } else {
            self.timer.value -= 1;
        }
    }

    fn stepSweep(self: *PulseChannel) void {
        self.sweep.step(&self.timer);
    }

    fn stepEnvelope(self: *PulseChannel) void {
        self.envelope.step(self.length_counter.halt);
    }

    fn gateSweep(self: PulseChannel) bool {
        return !self.sweep.isMuting(self.timer);
    }

    fn gateSequencer(self: PulseChannel) bool {
        return pulse_duty_values[self.duty_table][self.duty_index] != 0;
    }

    fn output(self: PulseChannel) u4 {
        if (self.gateSweep() and
            self.gateSequencer() and
            self.length_counter.gate())
        {
            return self.envelope.output();
        }
        return 0;
    }
};

const TriangleChannel = struct {
    duty_index: u5,

    timer: Timer(u11),
    linear_counter: LinearCounter,
    length_counter: LengthCounter,

    const LinearCounter = struct {
        value: u7,
        period: u7,
        reload: bool,

        fn reset(self: *LinearCounter) void {
            self.value = self.period;
        }
    };

    fn stepTimer(self: *TriangleChannel) void {
        if (self.timer.value == 0) {
            self.timer.reset();
            if (self.length_counter.value > 0 and self.linear_counter.value > 0) {
                self.duty_index +%= 1;
            }
        } else {
            self.timer.value -= 1;
        }
    }

    fn stepLinear(self: *TriangleChannel) void {
        if (self.linear_counter.reload) {
            self.linear_counter.reset();
        } else if (self.linear_counter.value > 0) {
            self.linear_counter.value -= 1;
        }
        if (!self.length_counter.halt) {
            self.linear_counter.reload = false;
        }
    }

    fn gateLinearCounter(self: TriangleChannel) bool {
        return self.linear_counter.value != 0;
    }

    fn output(self: TriangleChannel) u4 {
        if (self.gateLinearCounter() and self.length_counter.gate()) {
            return triangle_duty_values[self.duty_index];
        }
        return 0;
    }
};

pub const NoiseChannel = struct {
    timer: Timer(u13) = Timer(u13){},
    length_counter: LengthCounter = LengthCounter{},
    envelope: Envelope = Envelope{},

    shift: u15 = 1,
    mode: bool = false,

    fn stepTimer(self: *NoiseChannel) void {
        if (self.timer.value == 0) {
            self.timer.reset();

            const second_bit = if (self.mode) @as(u3, 6) else 1;
            const feedback: u1 = @truncate(u1, (self.shift & 1) ^ (self.shift >> second_bit));
            self.shift >>= 1;
            flags.setMask(u15, &self.shift, @as(u15, feedback) << 14, 0x4000);
        } else {
            self.timer.value -= 1;
        }
    }

    fn stepEnvelope(self: *NoiseChannel) void {
        self.envelope.step(self.length_counter.halt);
    }

    fn gateShift(self: NoiseChannel) bool {
        return !flags.getMaskBool(u15, self.shift, 1);
    }

    fn output(self: NoiseChannel) u4 {
        if (self.gateShift() and self.length_counter.gate()) {
            return self.envelope.output();
        }
        return 0;
    }
};
