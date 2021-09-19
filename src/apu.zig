const std = @import("std");
const audio = @import("sdl/audio.zig");
const AudioContext = audio.AudioContext;

const Cpu = @import("cpu.zig").Cpu;
const flags = @import("flags.zig");

const cpu_freq = 1789773;
const frame_counter_rate = 1 / 240.0;

const length_counter_table = [_]u8{
    10, 254, 20, 2,  40, 4,  80, 6,  160, 8,  60, 10, 14, 12, 26, 14,
    12, 16,  24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30,
};

const pulse_duty_values = [4][8]u8{
    [8]u8{ 0, 1, 0, 0, 0, 0, 0, 0 },
    [8]u8{ 0, 1, 1, 0, 0, 0, 0, 0 },
    [8]u8{ 0, 1, 1, 1, 1, 0, 0, 0 },
    [8]u8{ 1, 0, 0, 1, 1, 1, 1, 1 },
};

const triangle_duty_values = [_]u8{
    15, 14, 13, 12, 11, 10, 9, 8, 7, 6, 5,  4,  3,  2,  1,  0,
    0,  1,  2,  3,  4,  5,  6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
};

pub const Apu = struct {
    reg: Registers,

    cycles: usize = 0,
    frame_counter: usize = 0,
    audio_context: *AudioContext,

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

    // TODO: maybe rearrange stuff to avoid huge indentation levels
    pub const Registers = struct {
        pulse1: PulseChannel,
        pulse2: PulseChannel,
        triangle: TriangleChannel,
    };

    pub fn init(audio_context: *AudioContext) Apu {
        return Apu{
            .reg = std.mem.zeroes(Registers),

            .audio_context = audio_context,
        };
    }

    pub fn read(self: Apu, addr: u5) u8 {
        const reg = &self.reg;
        switch (addr) {
            0x15 => {
                var val: u8 = 0;
                val |= @as(u3, @boolToInt(reg.triangle.length_counter.value > 0)) << 2;
                val |= @as(u2, @boolToInt(reg.pulse2.length_counter.value > 0)) << 1;
                val |= @boolToInt(reg.pulse1.length_counter.value > 0);
                return val;
            },
            else => return 0,
        }
    }

    pub fn write(self: *Apu, addr: u5, val: u8) void {
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

            0x15 => {
                _ = flags.getMaskBool(u8, val, 0x10); // DMC enable
                _ = flags.getMaskBool(u8, val, 0x08); // noise length enable
                reg.triangle.length_counter.setEnabled(flags.getMaskBool(u8, val, 0x04));
                reg.pulse2.length_counter.setEnabled(flags.getMaskBool(u8, val, 0x02));
                reg.pulse1.length_counter.setEnabled(flags.getMaskBool(u8, val, 0x01));
            },
            else => {},
        }
    }

    fn stepQuarterFrame(self: *Apu) void {
        self.reg.pulse1.stepEnvelope();
        self.reg.pulse2.stepEnvelope();
        self.reg.triangle.stepLinear();
    }

    fn stepHalfFrame(self: *Apu) void {
        _ = self.reg.pulse1.length_counter.step();
        _ = self.reg.pulse2.length_counter.step();
        _ = self.reg.triangle.length_counter.step();

        self.reg.pulse1.stepSweep();
        self.reg.pulse2.stepSweep();
    }

    fn getOutput(self: *Apu) f32 {
        const p1_out = @intToFloat(f32, self.reg.pulse1.output());
        const p2_out = @intToFloat(f32, self.reg.pulse2.output());
        const pulse_out = 0.00752 * (p1_out + p2_out);
        const tnd_out = 0.00851 * @intToFloat(f32, self.reg.triangle.output());
        return pulse_out + tnd_out;
    }

    pub fn runCycle(self: *Apu) void {
        self.reg.triangle.stepTimer();
        if (self.cycles & 1 == 1) {
            self.reg.pulse1.stepTimer();
            self.reg.pulse2.stepTimer();
        }

        if (self.next_frame_counter_timer.isDone(self.cycles)) {
            // TODO: mode 1, interrupts
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
                },
            }
            self.frame_counter +%= 1;
            self.next_frame_counter_timer.setNext(@intToFloat(f32, cpu_freq) * frame_counter_rate);
        }

        if (self.next_output_timer.isDone(self.cycles)) {
            self.audio_context.addSample(self.getOutput()) catch {
                std.log.err("Couldn't add sample", .{});
            };
            self.next_output_timer.setNext(@intToFloat(f32, cpu_freq) / @intToFloat(f32, audio.sample_rate));
        }

        self.cycles +%= 1;
    }
};

const Timer = struct {
    value: u11,
    period: u11,

    fn reset(self: *Timer) void {
        self.value = self.period;
    }
};

const LengthCounter = struct {
    enabled: bool,
    halt: bool,
    value: u8,

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
    start: bool,
    constant_volume: bool,

    divider_counter: u5,
    divider_period: u4,
    decay_level_counter: u4,

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

    fn output(self: Envelope) u5 {
        if (self.constant_volume) {
            return self.divider_period;
        } else {
            return self.decay_level_counter;
        }
    }
};

const PulseChannel = struct {
    duty_table: u2,
    duty_index: u3,

    timer: Timer,
    length_counter: LengthCounter,

    sweep: Sweep,
    envelope: Envelope,

    // maybe put timer in sweep?
    const Sweep = struct {
        enabled: bool,
        negate: bool,
        reload: bool,
        divider_counter: u4,
        divider_period: u3,
        shift_count: u3,

        target_period: u12,

        fn isMuting(self: Sweep, timer: Timer) bool {
            return timer.period < 8 or flags.getMaskBool(u12, self.target_period, 0x800);
        }

        fn step(self: *Sweep, timer: *Timer) void {
            var delta: u10 = @truncate(u10, timer.period >> self.shift_count);
            if (self.negate) {
                // TODO: pulse1 = ~delta, pulse2 = ~delta + 1
                delta = ~delta +% 1;
            }

            self.target_period = @as(u12, timer.period) + delta;
            if (self.divider_counter == 0 and self.enabled and !self.isMuting(timer.*) and self.shift_count != 0) {
                timer.period = @truncate(u11, self.target_period);
            }
            if (self.divider_counter == 0 or self.reload) {
                self.divider_counter = @as(u4, self.divider_period);
                self.reload = false;
                return;
            } else {
                self.divider_counter -= 1;
            }
        }
    };

    /// addr = real address - 0x4000
    fn write(self: *PulseChannel, addr: u2, val: u8) void {
        switch (addr) {
            0x00 => {
                self.duty_table = @truncate(u2, val >> 6);
                self.length_counter.halt = flags.getMaskBool(u8, val, 0x20);
                self.envelope.constant_volume = flags.getMaskBool(u8, val, 0x10);
                self.envelope.divider_period = @truncate(u4, val); // + 1 ???
            },
            0x01 => {
                self.sweep.enabled = (val & 0x80) != 0;
                self.sweep.negate = (val & 0x08) != 0;
                self.sweep.reload = true;
                self.sweep.divider_period = @truncate(u3, val >> 4); // + 1 ???
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

    fn output(self: PulseChannel) u8 {
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

    timer: Timer,
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

    fn stepLength(self: *TriangleChannel) void {
        self.length_counter.step();
    }

    fn gateLinearCounter(self: TriangleChannel) bool {
        return self.linear_counter.value != 0;
    }

    fn output(self: TriangleChannel) u8 {
        if (self.gateLinearCounter() and self.length_counter.gate()) {
            return triangle_duty_values[self.duty_index];
        }
        return 0;
    }
};
