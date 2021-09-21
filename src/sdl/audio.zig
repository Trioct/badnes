const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @import("bindings.zig");

// TODO: make alternative that syncs video to audio instead of
// trying to sync audio to video
pub const Context = struct {
    device: sdl.c.SDL_AudioDeviceID,
    buffer: SampleBuffer,

    previous_sample: f32 = 0,

    pub const sample_rate = 44100 / 2;
    pub const sdl_buffer_size = 1024;

    const SampleBuffer = struct {
        samples: []f32,
        start: usize = 0,
        index: usize,
        preferred_size: usize,

        pub fn init(samples: []f32, preferred_size: usize) SampleBuffer {
            std.debug.assert(preferred_size < samples.len);

            std.mem.set(f32, samples[0..], 0);
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
            if (prev_order and (self.index < self.start)) {
                std.log.warn("Audio sample buffer ate its own tail", .{});
                self.index = self.start;
            }
        }
    };

    pub fn alloc(allocator: *Allocator) !Context {
        const buffer = try allocator.alloc(f32, Context.sample_rate);
        return Context{
            .device = undefined,
            .buffer = SampleBuffer.init(buffer, (Context.sample_rate / 6) - 1024),
        };
    }

    pub fn init(self: *Context) !void {
        var want = sdl.c.SDL_AudioSpec{
            .freq = sample_rate,
            .format = sdl.c.AUDIO_F32SYS,
            .channels = 1,
            .samples = sdl_buffer_size,
            .callback = audioCallback,
            .userdata = self,

            // readback variables
            .silence = 0,
            .padding = 0,
            .size = 0,
        };

        var have = std.mem.zeroes(sdl.c.SDL_AudioSpec);
        self.device = sdl.openAudioDevice(.{ null, 0, &want, &have, 0 });
        if (self.device == 0) {
            return sdl.SdlError.Error;
        }
        self.pause();
    }

    pub fn deinit(self: *Context, allocator: *Allocator) void {
        sdl.closeAudioDevice(.{self.device});
        allocator.free(self.buffer.samples);
    }

    pub fn pause(self: Context) void {
        sdl.pauseAudioDevice(.{ self.device, 1 });
    }

    pub fn unpause(self: Context) void {
        sdl.pauseAudioDevice(.{ self.device, 0 });
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

    fn audioCallback(user_data: ?*c_void, raw_buffer: [*c]u8, samples: c_int) callconv(.C) void {
        var context = @ptrCast(*Context, @alignCast(@sizeOf(@TypeOf(user_data)), user_data.?));
        var buffer = @ptrCast([*]f32, @alignCast(4, raw_buffer))[0..@intCast(usize, @divExact(samples, 4))];

        const ps = @intToFloat(f64, context.buffer.preferred_size);
        const length = @intToFloat(f64, context.buffer.length());
        //const copy_rate: f64 = 0.25 * (1 + length / ps);
        //const copy_rate: f64 = 0.25 * (length / ps - 1) + 1;
        const copy_rate: f64 = blk: {
            const temp = (length / ps) - 1;
            break :blk temp * temp * temp + 1;
        };
        //const copy_rate: f64 = (std.math.tanh(16 * (length - ps) / sample_rate) + 1) / 2;
        var copy_rem: f64 = 0;

        var i: usize = 0;
        if (copy_rate >= 1) {
            for (buffer) |*b| {
                b.* = context.buffer.get(i);

                const inc = copy_rate + copy_rem;
                i += @floatToInt(usize, @trunc(inc));
                copy_rem = @mod(inc, 1);
            }
        } else {
            for (buffer) |*b| {
                b.* = context.buffer.get(i);

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
