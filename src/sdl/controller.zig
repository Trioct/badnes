const std = @import("std");
const bindings = @import("bindings.zig");
const Sdl = bindings.Sdl;

const flags_ = @import("../flags.zig");
const CreateFlags = flags_.CreateFlags;
const FieldFlagsDef = flags_.FieldFlagsDef;

pub const Controller = struct {
    buttons: u8 = 0,
    shift: u4 = 0,
    read_input: bool = false,

    sdl_controller: ?*bindings.c.SDL_GameController = null,

    const ff_masks = CreateFlags(Controller, ([_]FieldFlagsDef{
        .{ .field = "buttons", .flags = "RLDUSsBA" },
    })[0..]){};

    pub fn strobe(self: *Controller) void {
        self.buttons = 0;
        self.shift = 0;

        if (!self.read_input) {
            return;
        }

        const keys = blk: {
            var length: c_int = 0;
            var ret: [*]const u8 = Sdl.getKeyboardState(.{&length});
            break :blk ret[0..@intCast(usize, length)];
        };

        if (keys[bindings.c.SDL_SCANCODE_RIGHT] != 0) {
            self.setButton("R");
        }
        if (keys[bindings.c.SDL_SCANCODE_LEFT] != 0) {
            self.setButton("L");
        }
        if (keys[bindings.c.SDL_SCANCODE_DOWN] != 0) {
            self.setButton("D");
        }
        if (keys[bindings.c.SDL_SCANCODE_UP] != 0) {
            self.setButton("U");
        }
        if (keys[bindings.c.SDL_SCANCODE_A] != 0) {
            self.setButton("S");
        }
        if (keys[bindings.c.SDL_SCANCODE_S] != 0) {
            self.setButton("s");
        }
        if (keys[bindings.c.SDL_SCANCODE_Z] != 0) {
            self.setButton("B");
        }
        if (keys[bindings.c.SDL_SCANCODE_X] != 0) {
            self.setButton("A");
        }

        // TODO: sdl controller stuff is all my personal buttons, remove
        if (self.sdl_controller) |c| {
            if (Sdl.gameControllerGetButton(.{ c, bindings.c.SDL_CONTROLLER_BUTTON_DPAD_RIGHT }) != 0) {
                self.setButton("R");
            }
            if (Sdl.gameControllerGetButton(.{ c, bindings.c.SDL_CONTROLLER_BUTTON_DPAD_LEFT }) != 0) {
                self.setButton("L");
            }
            if (Sdl.gameControllerGetButton(.{ c, bindings.c.SDL_CONTROLLER_BUTTON_DPAD_DOWN }) != 0) {
                self.setButton("D");
            }
            if (Sdl.gameControllerGetButton(.{ c, bindings.c.SDL_CONTROLLER_BUTTON_DPAD_UP }) != 0) {
                self.setButton("U");
            }
            if (Sdl.gameControllerGetButton(.{ c, bindings.c.SDL_CONTROLLER_BUTTON_START }) != 0) {
                self.setButton("S");
            }
            if (Sdl.gameControllerGetButton(.{ c, bindings.c.SDL_CONTROLLER_BUTTON_BACK }) != 0) {
                self.setButton("s");
            }
            if (Sdl.gameControllerGetButton(.{ c, bindings.c.SDL_CONTROLLER_BUTTON_Y }) != 0) {
                self.setButton("B");
            }
            if (Sdl.gameControllerGetButton(.{ c, bindings.c.SDL_CONTROLLER_BUTTON_A }) != 0) {
                self.setButton("B");
            }
            if (Sdl.gameControllerGetButton(.{ c, bindings.c.SDL_CONTROLLER_BUTTON_X }) != 0) {
                self.setButton("A");
            }
            if (Sdl.gameControllerGetButton(.{ c, bindings.c.SDL_CONTROLLER_BUTTON_B }) != 0) {
                self.setButton("A");
            }
        }
    }

    pub fn getNextButton(self: *Controller) u8 {
        if (self.shift < 8) {
            const val = (self.buttons >> @truncate(u3, self.shift)) & 1;
            self.shift += 1;
            return val;
        } else {
            return 1;
        }
    }

    pub fn setButton(self: *Controller, comptime button: []const u8) void {
        ff_masks.setFlag(self, .{ .flags = button }, true);
    }
};
