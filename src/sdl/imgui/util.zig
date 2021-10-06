const std = @import("std");
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
