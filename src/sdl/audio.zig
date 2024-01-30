const std = @import("std");
const Allocator = std.mem.Allocator;

const bindings = @import("bindings.zig");
const Sdl = bindings.Sdl;

// TODO: make alternative that syncs video to audio instead of
// trying to sync audio to video
pub const Context = struct {
    device: Sdl.AudioDeviceId,
    buffer: SampleBuffer,
    volume: f32 = 1.0,

    previous_sample: f32 = 0,

    pub const sample_rate = 44100 / 2;
    pub const sdl_buffer_size = 256;
    pub const sample_buffer_size = 1024;

    const SampleBuffer = struct {
        samples: []f32,
        start: usize = 0,
        index: usize,
        preferred_size: usize,

        pub fn init(samples: []f32, preferred_size: usize) SampleBuffer {
            std.debug.assert(preferred_size < samples.len);

            @memset(samples[0..], 0);
            return SampleBuffer{
                .samples = samples,
                .index = preferred_size,
                .preferred_size = preferred_size,
            };
        }

        pub fn convertIndex(self: SampleBuffer, index: usize) usize {
            return (self.start + index) % self.samples.len;
        }

        pub fn length(self: SampleBuffer) usize {
            return ((self.index + self.samples.len) - self.start) % self.samples.len;
        }

        pub fn get(self: SampleBuffer, index: usize) f32 {
            return self.samples[self.convertIndex(index)];
        }

        pub fn append(self: *SampleBuffer, val: f32) void {
            self.samples[self.index] = val;
            self.index = (self.index + 1) % self.samples.len;
        }

        pub fn truncateStart(self: *SampleBuffer, count: usize) void {
            const prev_order = self.index > self.start;
            self.start = (self.start + count) % self.samples.len;
            if (prev_order and self.index < self.start) {
                std.log.warn("Audio sample buffer ate its own tail", .{});
                self.index = self.start;
            }
        }
    };

    pub fn alloc(allocator: Allocator) !Context {
        const buffer = try allocator.alloc(f32, Context.sample_buffer_size * 2);
        return Context{
            .device = undefined,
            .buffer = SampleBuffer.init(buffer, sample_buffer_size),
        };
    }

    pub fn free(self: *Context, allocator: Allocator) void {
        allocator.free(self.buffer.samples);
    }

    pub fn init(self: *Context) !void {
        var want = Sdl.AudioSpec{
            .freq = sample_rate,
            .format = bindings.c.AUDIO_F32SYS,
            .channels = 1,
            .samples = sdl_buffer_size,
            .callback = audioCallback,
            .userdata = self,

            // readback variables
            .silence = 0,
            .padding = 0,
            .size = 0,
        };

        var have = std.mem.zeroes(Sdl.AudioSpec);
        self.device = Sdl.openAudioDevice(null, 0, &want, &have, 0);
        if (self.device == 0) {
            return Sdl.Error;
        }
        self.pause();
    }

    pub fn deinit(self: *Context, allocator: Allocator) void {
        Sdl.closeAudioDevice(self.device);
        self.free(allocator);
    }

    pub fn pause(self: Context) void {
        Sdl.pauseAudioDevice(self.device, 1);
    }

    pub fn unpause(self: Context) void {
        Sdl.pauseAudioDevice(self.device, 0);
    }

    pub fn addSample(self: *Context, val: f32) !void {
        const pi = std.math.pi;
        const high_pass1_a = (90 * pi) / (Context.sample_rate + 90 * pi);
        const high_pass2_a = (440 * pi) / (Context.sample_rate + 440 * pi);
        const low_pass_a = (14000 * pi) / (Context.sample_rate + 14000 * pi);

        const high_pass1 = high_pass1_a * val + (1 - high_pass1_a) * self.previous_sample;
        const high_pass2 = high_pass2_a * val + (1 - high_pass2_a) * high_pass1;
        const low_pass = low_pass_a * val + (1 - low_pass_a) * high_pass2;

        self.buffer.append(low_pass);
        self.previous_sample = low_pass;
    }

    fn audioCallback(user_data: ?*anyopaque, raw_buffer: [*c]u8, samples: c_int) callconv(.C) void {
        const context: *Context = @ptrCast(@alignCast(user_data.?));
        const buffer: []f32 = @as([*]f32, @ptrCast(@alignCast(raw_buffer)))[0..@intCast(@divExact(samples, 4))];

        const ps: f64 = @floatFromInt(context.buffer.preferred_size);
        const length: f64 = @floatFromInt(context.buffer.length());
        const err = (length - ps) / ps;

        const steepness: f64 = 10;
        const plateau_size: f64 = 0.7;

        const err_left = 1.0 / (1.0 + std.math.exp(steepness * (-plateau_size - err)));
        const err_right = 1.0 / (1.0 + std.math.exp(steepness * (plateau_size - err)));
        const err_smoothed = err_left + err_right - 1.0;
        const copy_rate = err_smoothed + 1.0;

        var copy_rem: f64 = 0;
        var i: usize = 0;
        if (copy_rate >= 1) {
            for (buffer) |*b| {
                b.* = context.buffer.get(i) * context.volume;

                const inc = copy_rate + copy_rem;
                i += @intFromFloat(@trunc(inc));
                copy_rem = @mod(inc, 1);
            }
        } else {
            for (buffer) |*b| {
                b.* = context.buffer.get(i) * context.volume;

                copy_rem += copy_rate;
                if (copy_rem > 1) {
                    i += 1;
                    copy_rem -= 1;
                }
            }
        }

        context.buffer.truncateStart(i);
    }
};
