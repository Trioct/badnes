const std = @import("std");
const Allocator = std.mem.Allocator;

const sdl = @import("bindings.zig");

pub const sample_rate = 44100;
pub const sdl_buffer_size = 512;

pub const AudioContext = struct {
    device: sdl.c.SDL_AudioDeviceID,
    buffer: SampleBuffer,

    const SampleBuffer = struct {
        bytes: []u8,
        start: usize = 0,
        index: usize,
        preferred_size: usize,

        pub fn init(bytes: []u8, preferred_size: usize) SampleBuffer {
            std.debug.assert(preferred_size < bytes.len);

            std.mem.set(u8, bytes[0..], 0);
            return SampleBuffer{
                .bytes = bytes,
                .index = preferred_size,
                .preferred_size = preferred_size,
            };
        }

        pub fn convertIndex(self: SampleBuffer, index: usize) usize {
            return (self.start + index) % self.bytes.len;
        }

        pub fn length(self: SampleBuffer) usize {
            return ((self.index + self.bytes.len) - self.start) % self.bytes.len;
        }

        pub fn get(self: SampleBuffer, index: usize) u8 {
            return self.bytes[self.convertIndex(index)];
        }

        pub fn append(self: *SampleBuffer, val: u8) void {
            self.bytes[self.index] = val;
            self.index = (self.index + 1) % self.bytes.len;
        }

        pub fn truncateStart(self: *SampleBuffer, count: usize) void {
            const prev_order = self.index > self.start;
            self.start = (self.start + count) % self.bytes.len;
            if (prev_order and (self.index < self.start)) {
                std.debug.print("bap\n", .{});
                self.index = self.start;
            }
        }
    };

    pub fn alloc(allocator: *Allocator) !AudioContext {
        const buffer = try allocator.alloc(u8, sample_rate);
        return AudioContext{
            .device = undefined,
            .buffer = SampleBuffer.init(buffer, sample_rate / 4),
        };
    }

    pub fn init(self: *AudioContext) !void {
        var want = sdl.c.SDL_AudioSpec{
            .freq = sample_rate,
            //.format = sdl.c.AUDIO_U8,
            .format = sdl.c.AUDIO_S16SYS,
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
        allocator.free(self.buffer.bytes);
    }

    pub fn pause(self: AudioContext) void {
        sdl.pauseAudioDevice(.{ self.device, 1 });
    }

    pub fn unpause(self: AudioContext) void {
        sdl.pauseAudioDevice(.{ self.device, 0 });
    }

    pub fn addSample(self: *AudioContext, val: u8) !void {
        self.buffer.append(val);
    }

    fn audioCallback(user_data: ?*c_void, raw_buffer: [*c]u8, bytes: c_int) callconv(.C) void {
        var context = @ptrCast(*AudioContext, @alignCast(@sizeOf(@TypeOf(user_data)), user_data.?));
        //var buffer = raw_buffer[0..@intCast(usize, bytes)];
        var buffer = @ptrCast([*]i16, @alignCast(2, raw_buffer))[0..@intCast(usize, @divExact(bytes, 2))];

        const ps = @intToFloat(f64, context.buffer.preferred_size);
        const length = @intToFloat(f64, context.buffer.length());
        const duplicate_interval: f64 = 10 / (ps / length - 1);
        var duplicate_counter: f64 = 0;
        const no_duplicate = duplicate_interval <= 1;

        std.debug.print("{d} {d}\n", .{ duplicate_interval, length });

        var i: usize = 0;
        for (buffer) |*b| {
            b.* = @as(i16, context.buffer.get(i)) * 256;
            duplicate_counter += 1;
            if (!no_duplicate and duplicate_counter > duplicate_interval) {
                duplicate_counter -= duplicate_interval;
            } else {
                i += 1;
            }
        }
        context.buffer.truncateStart(i);
    }
};
