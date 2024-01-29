const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayListUnmanaged;

const IoMethod = @import("console.zig").IoMethod;

const flags_ = @import("flags.zig");
const CreateFlags = flags_.CreateFlags;
const FieldFlagsDef = flags_.FieldFlagsDef;

pub fn Controller(comptime method: IoMethod) type {
    switch (method) {
        .pure => return PureController,
        .sdl => return @import("sdl/controller.zig").Controller,
    }
}

pub const PureController = struct {
    buttons: u8 = 0,
    buttons_reload: u8 = 0,
    shift: u4 = 0,

    const Flags = CreateFlags(PureController, &.{
        .{ .field = .buttons_reload, .flags = "RLDUSsBA" },
    });

    pub fn strobe(self: *PureController) void {
        self.buttons = self.buttons_reload;
        self.shift = 0;
    }

    pub fn getNextButton(self: *PureController) u8 {
        if (self.shift < 8) {
            const val = (self.buttons >> @truncate(self.shift)) & 1;
            self.shift += 1;
            return val;
        } else {
            return 1;
        }
    }

    pub fn holdButtons(self: *PureController, comptime buttons: []const u8) void {
        Flags.setFlags(self, .{ .flags = buttons }, 0xff);
    }
};
