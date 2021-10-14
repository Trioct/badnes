const std = @import("std");
const time = std.time;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

pub const StringBuilder = struct {
    buffer: ArrayList(u8),

    pub fn init(allocator: *Allocator) StringBuilder {
        return StringBuilder{
            .buffer = ArrayList(u8).init(allocator),
        };
    }

    pub fn initCapacity(allocator: *Allocator, capacity: usize) !StringBuilder {
        return StringBuilder{
            .buffer = try ArrayList(u8).initCapacity(allocator, capacity),
        };
    }

    pub fn deinit(self: StringBuilder) void {
        self.buffer.deinit();
    }

    pub fn getSlice(self: *StringBuilder) []u8 {
        return self.buffer.items;
    }

    pub fn getSliceNull(self: *StringBuilder) [:0]u8 {
        return self.buffer.items[0 .. self.buffer.items.len - 1 :0];
    }

    pub fn toOwnedSlice(self: *StringBuilder) []u8 {
        return self.buffer.toOwnedSlice();
    }

    pub fn toOwnedSliceNull(self: *StringBuilder) ![:0]u8 {
        try self.buffer.append('\x00');
        const bytes = self.buffer.toOwnedSlice();
        return @ptrCast([*:0]u8, bytes)[0 .. bytes.len - 1 :0];
    }

    pub fn toRefBuffer(self: *StringBuilder, allocator: *Allocator) !RefBuffer(u8) {
        return RefBuffer(u8).from(allocator, self.toOwnedSlice());
    }

    /// Resets len, but not capacity, memory is not freed
    pub fn reset(self: *StringBuilder) void {
        self.buffer.resize(0) catch unreachable;
    }

    pub fn clearAndFree(self: *StringBuilder) void {
        self.buffer.clearAndFree();
    }

    pub fn writer(self: *StringBuilder) std.io.Writer(*StringBuilder, Allocator.Error, StringBuilder.write) {
        return .{ .context = self };
    }

    pub fn write(self: *StringBuilder, bytes: []const u8) Allocator.Error!usize {
        try self.buffer.appendSlice(bytes);
        return bytes.len;
    }
};

pub fn RefBuffer(comptime T: type) type {
    return struct {
        const Self = @This();

        allocator: *Allocator,
        slice: []T,
        ref_count: *usize,

        pub fn init(allocator: *Allocator, size: usize) !Self {
            return Self.from(allocator, try allocator.alloc(T, size));
        }

        pub fn from(allocator: *Allocator, slice: []T) !Self {
            errdefer allocator.free(slice);
            var ref_count = try allocator.create(usize);
            ref_count.* = 1;
            return Self{
                .allocator = allocator,
                .slice = slice,
                .ref_count = ref_count,
            };
        }

        pub fn ref(self: Self) Self {
            self.ref_count.* += 1;
            return self;
        }

        pub fn unref(self: Self) void {
            self.ref_count.* -= 1;
            if (self.ref_count.* == 0) {
                self.allocator.free(self.slice);
                self.allocator.destroy(self.ref_count);
            }
        }
    };
}

pub const FrameTimer = struct {
    pub const ntsc_frame_time: f64 = (4 * (261 * 341 + 340.5)) / 21477272.0;
    frame_time: f64,

    paused_timestamp: ?i128 = null,
    last_frame_timestamp: i128,
    next_frame_timestamp: i128,

    pub const TimingMethod = enum {
        no_sleep,
        sleep,
    };

    pub const CheckResult = struct {
        ns_passed: i128,
        frames_passed: usize,
    };

    pub fn init(frame_time: ?f64) FrameTimer {
        const ft_default = frame_time orelse ntsc_frame_time;
        const now = time.nanoTimestamp();
        return FrameTimer{
            .frame_time = ft_default,
            .last_frame_timestamp = now,
            .next_frame_timestamp = now + @floatToInt(i128, time.ns_per_s * ft_default),
        };
    }

    /// Giveup_frames is how many frames we can be behind before giving up and
    /// Resetting the goal for the timer
    pub fn check(self: *FrameTimer, method: TimingMethod, giveup_frames: ?usize) CheckResult {
        const frame_ns = @floatToInt(i128, time.ns_per_s * self.frame_time);
        const now = time.nanoTimestamp();
        var passed = now - self.last_frame_timestamp;

        switch (method) {
            .no_sleep => {},
            .sleep => {
                const to_sleep = self.next_frame_timestamp - now;
                if (to_sleep > 0) {
                    time.sleep(@intCast(u64, to_sleep));
                    passed += to_sleep;
                }
            },
        }

        const old_last = self.last_frame_timestamp;
        self.last_frame_timestamp += passed;
        const frames_passed = @divTrunc(self.last_frame_timestamp, frame_ns) - @divTrunc(old_last, frame_ns);

        if (giveup_frames) |gf| {
            const time_behind = self.last_frame_timestamp - self.next_frame_timestamp;
            const frames_behind = @divTrunc(time_behind, frame_ns);
            if (frames_behind >= gf) {
                std.log.debug(
                    "We fell {} frames behind the timer (> {} frames), resetting timer",
                    .{ frames_behind, gf },
                );
                self.next_frame_timestamp = self.last_frame_timestamp;
            }
        }
        if (self.last_frame_timestamp >= self.next_frame_timestamp) {
            self.next_frame_timestamp += frame_ns;
        }

        return CheckResult{
            .ns_passed = passed,
            .frames_passed = @intCast(usize, frames_passed),
        };
    }

    pub fn pause(self: *FrameTimer) void {
        if (self.paused_timestamp != null) {
            std.log.warn("Tried to pause an already paused FrameTimer", .{});
            return;
        }
        self.paused_timestamp = time.nanoTimestamp();
    }

    pub fn unpause(self: *FrameTimer) void {
        const paused_timestamp = self.paused_timestamp orelse {
            std.log.warn("Tried to unpause an already unpaused FrameTimer", .{});
            return;
        };

        const now = time.nanoTimestamp();
        const passed = now - paused_timestamp;

        self.last_frame_timestamp += passed;
        self.next_frame_timestamp += passed;

        self.paused_timestamp = null;
    }
};

const testing = std.testing;
const expectEqual = testing.expectEqual;
const expectEqualSlices = testing.expectEqualSlices;

test "StringBuilder" {
    var str = StringBuilder.init(testing.allocator);
    defer str.deinit();

    _ = try str.write("Hell");
    _ = try std.fmt.format(str.writer(), "o, {s}!", .{"World"});

    const str_owned = str.toOwnedSlice();
    defer testing.allocator.free(str_owned);

    try expectEqualSlices(u8, "Hello, World!", str_owned);

    _ = try std.fmt.format(str.writer(), "Goodbye, World!", .{});
    try expectEqualSlices(u8, "Goodbye, World!", str.buffer.items);

    str.reset();
    _ = try std.fmt.format(str.writer(), "{} + {} = ???", .{ 9, 10 });

    try expectEqualSlices(u8, "9 + 10 = ???", str.buffer.items);
    try expectEqualSlices(u8, "Hello, World!", str_owned);
}

test "RefBuffer" {
    const meme = "it's me, chris pratt.";
    const ref = blk: {
        const scoped = try RefBuffer(u8).init(testing.allocator, meme.len);
        defer scoped.unref();

        std.mem.copy(u8, scoped.slice, meme);

        break :blk scoped.ref();
    };
    defer ref.unref();

    ref.ref().unref();
    ref.ref().unref();
    ref.ref().unref();

    try expectEqual(@as(usize, 1), ref.ref_count.*);
    try expectEqualSlices(u8, meme, ref.slice);
}
