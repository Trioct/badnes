const std = @import("std");
const bindings = @import("bindings.zig");
const Sdl = bindings.Sdl;

const flags_ = @import("../flags.zig");
const CreateFlags = flags_.CreateFlags;
const FieldFlagsDef = flags_.FieldFlagsDef;

pub const Controller = struct {
    buttons: u8 = 0,
    shift: u4 = 0,

    const Flags = CreateFlags(Controller, &.{
        .{ .field = .buttons, .flags = "RLDUSsBA" },
    });

    pub fn strobe(self: *Controller) void {
        const keys = blk: {
            var length: c_int = 0;
            var ret: [*]const u8 = Sdl.getKeyboardState(&length);
            break :blk ret[0..@intCast(length)];
        };

        self.buttons = 0;
        self.shift = 0;

        inline for (&.{
            .{ bindings.c.SDL_SCANCODE_RIGHT, "R" },
            .{ bindings.c.SDL_SCANCODE_LEFT, "L" },
            .{ bindings.c.SDL_SCANCODE_DOWN, "D" },
            .{ bindings.c.SDL_SCANCODE_UP, "U" },
            .{ bindings.c.SDL_SCANCODE_A, "S" },
            .{ bindings.c.SDL_SCANCODE_S, "s" },
            .{ bindings.c.SDL_SCANCODE_Z, "B" },
            .{ bindings.c.SDL_SCANCODE_X, "A" },
        }) |pair| {
            if (keys[pair.@"0"] != 0) {
                self.setButton(pair.@"1");
            }
        }
    }

    pub fn getNextButton(self: *Controller) u8 {
        if (self.shift < 8) {
            const val = (self.buttons >> @truncate(self.shift)) & 1;
            self.shift += 1;
            return val;
        } else {
            return 1;
        }
    }

    pub fn setButton(self: *Controller, comptime button: []const u8) void {
        Flags.setFlag(self, .{ .flags = button }, true);
    }
};
