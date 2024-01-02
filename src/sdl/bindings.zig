const std = @import("std");
const build_options = @import("build_options");

pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_audio.h");
    @cInclude("SDL2/SDL_opengl.h");
});

pub const Sdl = struct {
    const empty_options = .{ .sdl = .{} };
    pub const Error = CError.SdlError;

    pub const Window = c.SDL_Window;
    pub const GLContext = c.SDL_GLContext;
    pub const Event = c.SDL_Event;
    pub const AudioDeviceId = c.SDL_AudioDeviceID;
    pub const AudioSpec = c.SDL_AudioSpec;

    pub const init_timer = c.SDL_INIT_TIMER;
    pub const init_audio = c.SDL_INIT_AUDIO;
    pub const init_video = c.SDL_INIT_VIDEO;
    pub const init_joystick = c.SDL_INIT_JOYSTICK;
    pub const init_haptic = c.SDL_INIT_HAPTIC;
    pub const init_gamecontroller = c.SDL_INIT_GAMECONTROLLER;
    pub const init_events = c.SDL_INIT_EVENTS;
    pub const init_everything = c.SDL_INIT_EVERYTHING;

    pub const init = wrap(c.SDL_Init, empty_options);
    pub const quit = wrap(c.SDL_Quit, empty_options);

    pub const glCreateContext = wrap(c.SDL_GL_CreateContext, empty_options);
    pub const glDeleteContext = wrap(c.SDL_GL_DeleteContext, empty_options);

    pub const glSetAttribute = wrap(c.SDL_GL_SetAttribute, empty_options);
    pub const glMakeCurrent = wrap(c.SDL_GL_MakeCurrent, empty_options);
    pub const glSetSwapInterval = wrap(c.SDL_GL_SetSwapInterval, empty_options);
    pub const glSwapWindow = wrap(c.SDL_GL_SwapWindow, empty_options);

    pub const createWindow = wrap(c.SDL_CreateWindow, empty_options);
    pub const destroyWindow = wrap(c.SDL_DestroyWindow, empty_options);
    pub const getWindowSize = wrap(c.SDL_GetWindowSize, empty_options);
    pub const setWindowSize = wrap(c.SDL_SetWindowSize, empty_options);
    pub const setWindowPosition = wrap(c.SDL_SetWindowPosition, empty_options);

    pub const pollEvent = wrap(c.SDL_PollEvent, .{ .sdl = .{ .int = .int_to_zig } });
    pub const getKeyboardState = wrap(c.SDL_GetKeyboardState, .{ .sdl = .{
        .many_ptr_to_single = false,
    } });

    pub const openAudioDevice = wrap(c.SDL_OpenAudioDevice, .{ .sdl = .{ .int = null } });
    pub const closeAudioDevice = wrap(c.SDL_CloseAudioDevice, empty_options);
    pub const pauseAudioDevice = wrap(c.SDL_PauseAudioDevice, empty_options);
};

pub const Gl = struct {
    const empty_options = .{ .opengl = .{} };
    pub const Error = CError.GlError;

    pub const Int = c.GLint;
    pub const Uint = c.GLuint;
    pub const Sizei = c.GLsizei;
    pub const Float = c.GLfloat;
    pub const Void = c.GLvoid;

    pub const viewport = wrap(c.glViewport, empty_options);
    pub const enable = wrap(c.glEnable, empty_options);

    pub const clearColor = wrap(c.glClearColor, .{ .opengl = .{ .check_error = false } });
    pub const clear = wrap(c.glClear, empty_options);

    pub const pushClientAttrib = wrap(c.glPushClientAttrib, empty_options);
    pub const popClientAttrib = wrap(c.glPopClientAttrib, empty_options);
    pub const enableClientState = wrap(c.glEnableClientState, empty_options);
    pub const disableClientState = wrap(c.glDisableClientState, empty_options);

    pub const pushMatrix = wrap(c.glPushMatrix, empty_options);
    pub const popMatrix = wrap(c.glPopMatrix, empty_options);
    pub const loadIdentity = wrap(c.glLoadIdentity, empty_options);
    pub const ortho = wrap(c.glOrtho, empty_options);
    pub const matrixMode = wrap(c.glMatrixMode, empty_options);

    pub const genTextures = wrap(c.glGenTextures, empty_options);
    pub const deleteTextures = wrap(c.glDeleteTextures, empty_options);
    pub const bindTexture = wrap(c.glBindTexture, empty_options);
    pub const texImage2D = wrap(c.glTexImage2D, empty_options);
    pub const texParameteri = wrap(c.glTexParameteri, empty_options);

    pub const vertexPointer = wrap(c.glVertexPointer, empty_options);
    pub const texCoordPointer = wrap(c.glTexCoordPointer, empty_options);
    pub const drawArrays = wrap(c.glDrawArrays, empty_options);
};

pub const CError = error{
    SdlError,
    GlError,
};

fn errorFromOptions(comptime options: WrapOptions) CError {
    return switch (options) {
        .sdl => CError.SdlError,
        .opengl => CError.GlError,
    };
}

const WrapOptions = union(enum) {
    sdl: struct {
        int: ?IntConversion = .int_to_error,
        optional_to_error: bool = true,
        many_ptr_to_single: bool = true,
    },

    // whether to check glGetError
    opengl: struct {
        check_error: bool = true,
    },

    const IntConversion = enum {
        int_to_error,
        int_to_zig,
    };

    fn intConversion(comptime self: WrapOptions) ?IntConversion {
        return switch (self) {
            .sdl => |x| x.int,
            .opengl => null,
        };
    }

    fn boolToError(comptime self: WrapOptions) bool {
        return switch (self) {
            .sdl => false,
            .opengl => false,
        };
    }

    fn optionalToError(comptime self: WrapOptions) bool {
        return switch (self) {
            .sdl => |x| x.optional_to_error,
            .opengl => false,
        };
    }

    fn manyPtrToSingle(comptime self: WrapOptions) bool {
        return switch (self) {
            .sdl => |x| x.many_ptr_to_single,
            .opengl => false,
        };
    }
};

fn WrappedCallReturn(comptime T: type, comptime options: WrapOptions) type {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .Int => if (comptime options.intConversion()) |int| {
            switch (int) {
                .int_to_error => return CError!void,
                .int_to_zig => if (T == c_int) {
                    const c_int_info = @typeInfo(c_int).Int;
                    return @Type(.{
                        .Int = .{ .signedness = c_int_info.signedness, .bits = c_int_info.bits },
                    });
                } else {
                    return T;
                },
            }
        } else {
            return T;
        },
        .Bool => if (comptime options.boolToError()) {
            return CError!void;
        } else {
            return bool;
        },
        .Optional => |optional| if (comptime options.optionalToError()) {
            return CError!optional.child;
        } else {
            return T;
        },
        .Pointer => |pointer| switch (pointer.size) {
            .C => if (comptime options.manyPtrToSingle()) {
                return CError!*pointer.child;
            } else {
                return T;
            },
            else => return T,
        },
        else => return T,
    }
}

fn WrappedCheckedReturn(comptime T: type, comptime options: WrapOptions) type {
    switch (options) {
        .sdl => return T,
        .opengl => |x| {
            std.debug.assert(T == void);
            if (x.check_error) {
                return CError!void;
            } else {
                return void;
            }
        },
    }
}

fn WrappedFinalReturn(comptime T: type, comptime options: WrapOptions) type {
    return WrappedCheckedReturn(WrappedCallReturn(T, options), options);
}

fn ReturnType(comptime T: type) type {
    switch (@typeInfo(T)) {
        .Fn => |func_info| {
            if (func_info.return_type) |t| {
                return t;
            } else {
                @compileError("Function has no return type");
            }
        },
        else => @compileError("Can't wrap a non-function"),
    }
}

fn WrappedSignature(comptime T: type, comptime options: WrapOptions) type {
    const RetType = WrappedFinalReturn(ReturnType(T), options);
    switch (@typeInfo(T)) {
        .Fn => |func_info| {
            const params = func_info.params;
            return switch (func_info.params.len) {
                0 => fn () RetType,
                1 => fn (params[0].type.?) RetType,
                2 => fn (params[0].type.?, params[1].type.?) RetType,
                3 => fn (
                    params[0].type.?,
                    params[1].type.?,
                    params[2].type.?,
                ) RetType,
                4 => fn (
                    params[0].type.?,
                    params[1].type.?,
                    params[2].type.?,
                    params[3].type.?,
                ) RetType,
                5 => fn (
                    params[0].type.?,
                    params[1].type.?,
                    params[2].type.?,
                    params[3].type.?,
                    params[4].type.?,
                ) RetType,
                6 => fn (
                    params[0].type.?,
                    params[1].type.?,
                    params[2].type.?,
                    params[3].type.?,
                    params[4].type.?,
                    params[5].type.?,
                ) RetType,
                else => fn (anytype) RetType,
            };
        },
        else => @compileError("Can't wrap a non-function"),
    }
}

fn wrapReturn(ret_val: anytype, comptime options: WrapOptions) WrappedCallReturn(@TypeOf(ret_val), options) {
    const T = @TypeOf(ret_val);
    const RetType = WrappedCallReturn(T, options);
    const type_info = @typeInfo(@TypeOf(ret_val));
    switch (type_info) {
        .Int => if (comptime options.intConversion()) |int| {
            switch (int) {
                .int_to_error => if (ret_val == 0) {
                    return;
                } else {
                    return errorFromOptions(options);
                },
                .int_to_zig => {
                    return @as(RetType, ret_val);
                },
            }
        } else {
            return ret_val;
        },
        .Bool => if (comptime options.boolToError()) {
            if (ret_val) {
                return;
            } else {
                return errorFromOptions(options);
            }
        } else {
            return ret_val;
        },
        .Optional => if (comptime options.optionalToError()) {
            if (ret_val) |val| {
                return val;
            } else {
                return errorFromOptions(options);
            }
        } else {
            return ret_val;
        },
        .Pointer => |pointer| switch (pointer.size) {
            .C => if (comptime options.manyPtrToSingle()) {
                if (ret_val != 0) {
                    return @ptrCast(ret_val);
                } else {
                    return errorFromOptions(options);
                }
            } else {
                return ret_val;
            },
            else => return ret_val,
        },
        else => return ret_val,
    }
}

fn wrapPrintError(
    comptime options: WrapOptions,
    ret_val: anytype,
) WrappedCheckedReturn(@TypeOf(ret_val), options) {
    const is_error =
        switch (@typeInfo(@TypeOf(ret_val))) {
        .ErrorUnion => std.meta.isError(ret_val),
        else => false,
    };
    switch (options) {
        .sdl => if (is_error) {
            std.log.err("{s}", .{c.SDL_GetError()});
        },
        .opengl => |gl_options| {
            if (gl_options.check_error) {
                var err = c.glGetError();
                const has_error = err != c.GL_NO_ERROR;

                while (err != c.GL_NO_ERROR) : (err = c.glGetError()) {
                    std.log.err("{}", .{err});
                }

                if (has_error) {
                    return CError.GlError;
                }
            }
        },
    }
    return ret_val;
}

fn wrap(
    comptime func: anytype,
    comptime options: WrapOptions,
) WrappedSignature(@TypeOf(func), options) {
    const T = @TypeOf(func);
    const RetType = WrappedFinalReturn(ReturnType(T), options);
    switch (@typeInfo(@TypeOf(func))) {
        .Fn => |func_info| {
            return switch (func_info.params.len) {
                0 => struct {
                    fn f() RetType {
                        return wrapPrintError(options, wrapReturn(func(), options));
                    }
                },
                1 => struct {
                    const A1 = func_info.params[0].type.?;
                    fn f(a1: A1) RetType {
                        return wrapPrintError(options, wrapReturn(func(a1), options));
                    }
                },
                2 => struct {
                    const A1 = func_info.params[0].type.?;
                    const A2 = func_info.params[1].type.?;
                    fn f(a1: A1, a2: A2) RetType {
                        return wrapPrintError(options, wrapReturn(func(a1, a2), options));
                    }
                },
                3 => struct {
                    const A1 = func_info.params[0].type.?;
                    const A2 = func_info.params[1].type.?;
                    const A3 = func_info.params[2].type.?;
                    fn f(a1: A1, a2: A2, a3: A3) RetType {
                        return wrapPrintError(options, wrapReturn(func(a1, a2, a3), options));
                    }
                },
                4 => struct {
                    const A1 = func_info.params[0].type.?;
                    const A2 = func_info.params[1].type.?;
                    const A3 = func_info.params[2].type.?;
                    const A4 = func_info.params[3].type.?;
                    fn f(a1: A1, a2: A2, a3: A3, a4: A4) RetType {
                        return wrapPrintError(
                            options,
                            wrapReturn(func(a1, a2, a3, a4), options),
                        );
                    }
                },
                5 => struct {
                    const A1 = func_info.params[0].type.?;
                    const A2 = func_info.params[1].type.?;
                    const A3 = func_info.params[2].type.?;
                    const A4 = func_info.params[3].type.?;
                    const A5 = func_info.params[4].type.?;
                    fn f(a1: A1, a2: A2, a3: A3, a4: A4, a5: A5) RetType {
                        return wrapPrintError(
                            options,
                            wrapReturn(func(a1, a2, a3, a4, a5), options),
                        );
                    }
                },
                6 => struct {
                    const A1 = func_info.params[0].type.?;
                    const A2 = func_info.params[1].type.?;
                    const A3 = func_info.params[2].type.?;
                    const A4 = func_info.params[3].type.?;
                    const A5 = func_info.params[4].type.?;
                    const A6 = func_info.params[5].type.?;
                    fn f(a1: A1, a2: A2, a3: A3, a4: A4, a5: A5, a6: A6) RetType {
                        return wrapPrintError(
                            options,
                            wrapReturn(func(a1, a2, a3, a4, a5, a6), options),
                        );
                    }
                },
                else => struct {
                    fn f(args: anytype) RetType {
                        return wrapPrintError(options, @call(.auto, func, args));
                    }
                },
            }.f;
        },
        else => @compileError("Can't wrap a non-function"),
    }
}
