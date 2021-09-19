const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @import("bindings.zig");

pub const sample_rate = 44100 / 2;
pub const sdl_buffer_size = 1024;

// TODO: make alternative that syncs video to audio instead of
// trying to sync audio to video
pub const AudioContext = struct {
    device: sdl.c.SDL_AudioDeviceID,
    buffer: SampleBuffer,

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

    pub fn alloc(allocator: *Allocator) !AudioContext {
        const buffer = try allocator.alloc(f32, sample_rate);
        return AudioContext{
            .device = undefined,
            .buffer = SampleBuffer.init(buffer, (sample_rate / 6) - 1024),
        };
    }

    pub fn init(self: *AudioContext) !void {
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

    pub fn deinit(self: *AudioContext, allocator: *Allocator) void {
        sdl.closeAudioDevice(.{self.device});
        allocator.free(self.buffer.samples);
    }

    pub fn pause(self: AudioContext) void {
        sdl.pauseAudioDevice(.{ self.device, 1 });
    }

    pub fn unpause(self: AudioContext) void {
        sdl.pauseAudioDevice(.{ self.device, 0 });
    }

    pub fn addSample(self: *AudioContext, val: f32) !void {
        self.buffer.append(val);
    }

    fn audioCallback(user_data: ?*c_void, raw_buffer: [*c]u8, samples: c_int) callconv(.C) void {
        var context = @ptrCast(*AudioContext, @alignCast(@sizeOf(@TypeOf(user_data)), user_data.?));
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
