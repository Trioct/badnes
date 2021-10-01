const std = @import("std");
pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_audio.h");
    @cInclude("SDL2/SDL_opengl.h");
});

pub const Sdl = struct {
    pub const Window = c.SDL_Window;
    pub const GLContext = c.SDL_GLContext;

    pub const init = wrap(c.SDL_Init, .{ .sdl = .{} });
    pub const quit = wrap(c.SDL_Quit, .{ .sdl = .{} });

    pub const glCreateContext = wrap(c.SDL_GL_CreateContext, .{ .sdl = .{} });
    pub const glDeleteContext = wrap(c.SDL_GL_DeleteContext, .{ .sdl = .{} });

    pub const glSetAttribute = wrap(c.SDL_GL_SetAttribute, .{ .sdl = .{} });
    pub const glMakeCurrent = wrap(c.SDL_GL_MakeCurrent, .{ .sdl = .{} });
    pub const glSetSwapInterval = wrap(c.SDL_GL_SetSwapInterval, .{ .sdl = .{} });
    pub const glSwapWindow = wrap(c.SDL_GL_SwapWindow, .{ .sdl = .{} });

    pub const createWindow = wrap(c.SDL_CreateWindow, .{ .sdl = .{} });
    pub const destroyWindow = wrap(c.SDL_DestroyWindow, .{ .sdl = .{} });
    pub const getWindowSize = wrap(c.SDL_GetWindowSize, .{ .sdl = .{} });

    pub const pollEvent = wrap(c.SDL_PollEvent, .{ .sdl = .{ .int = .int_to_zig } });
    pub const getKeyboardState = wrap(c.SDL_GetKeyboardState, .{ .sdl = .{
        .many_ptr_to_single = false,
    } });

    pub const openAudioDevice = wrap(c.SDL_OpenAudioDevice, .{ .sdl = .{ .int = null } });
    pub const closeAudioDevice = wrap(c.SDL_CloseAudioDevice, .{ .sdl = .{} });
    pub const pauseAudioDevice = wrap(c.SDL_PauseAudioDevice, .{ .sdl = .{} });
};

pub const Gl = struct {
    pub const viewport = wrap(c.glViewport, .{ .opengl = .{} });
    pub const enable = wrap(c.glEnable, .{ .opengl = .{} });

    pub const clearColor = wrap(c.glClearColor, .{ .opengl = .{ .check_error = false } });
    pub const clear = wrap(c.glClear, .{ .opengl = .{} });

    pub const pushClientAttrib = wrap(c.glPushClientAttrib, .{ .opengl = .{} });
    pub const popClientAttrib = wrap(c.glPopClientAttrib, .{ .opengl = .{} });
    pub const enableClientState = wrap(c.glEnableClientState, .{ .opengl = .{} });
    pub const disableClientState = wrap(c.glDisableClientState, .{ .opengl = .{} });

    pub const pushMatrix = wrap(c.glPushMatrix, .{ .opengl = .{} });
    pub const popMatrix = wrap(c.glPopMatrix, .{ .opengl = .{} });
    pub const loadIdentity = wrap(c.glLoadIdentity, .{ .opengl = .{} });
    pub const ortho = wrap(c.glOrtho, .{ .opengl = .{} });
    pub const matrixMode = wrap(c.glMatrixMode, .{ .opengl = .{} });

    pub const genTextures = wrap(c.glGenTextures, .{ .opengl = .{} });
    pub const deleteTextures = wrap(c.glDeleteTextures, .{ .opengl = .{} });
    pub const bindTexture = wrap(c.glBindTexture, .{ .opengl = .{} });
    pub const texImage2D = wrap(c.glTexImage2D, .{ .opengl = .{} });
    pub const texParameteri = wrap(c.glTexParameteri, .{ .opengl = .{} });

    pub const vertexPointer = wrap(c.glVertexPointer, .{ .opengl = .{} });
    pub const texCoordPointer = wrap(c.glTexCoordPointer, .{ .opengl = .{} });
    pub const drawArrays = wrap(c.glDrawArrays, .{ .opengl = .{} });
};

pub const CError = error{
    SdlError,
    GlError,
};

const WrapOptions = union(enum) {
    sdl: struct {
        int: ?enum {
            int_to_error,
            int_to_zig,
        } = .int_to_error,
        optional_to_error: bool = true,
        many_ptr_to_single: bool = true,
    },

    // whether to check glGetError
    opengl: struct {
        check_error: bool = true,
    },
};

fn WrappedCallReturn(comptime T: type, comptime options: WrapOptions) type {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .Int => if (options.sdl.int) |int| {
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
        .Optional => |optional| if (options.sdl.optional_to_error) {
            return CError!optional.child;
        } else {
            return T;
        },
        .Pointer => |pointer| switch (pointer.size) {
            .C => if (options.sdl.many_ptr_to_single) {
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
        .opengl => {
            std.debug.assert(T == void);
            return CError!void;
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
            if (func_info.args.len == 0) {
                return (fn () RetType);
            } else {
                return (fn (anytype) RetType);
            }
        },
        else => @compileError("Can't wrap a non-function"),
    }
}

fn wrapReturn(ret_val: anytype, comptime options: WrapOptions) WrappedCallReturn(@TypeOf(ret_val), options) {
    const T = @TypeOf(ret_val);
    const RetType = WrappedCallReturn(T, options);
    const type_info = @typeInfo(@TypeOf(ret_val));
    switch (type_info) {
        .Int => if (options.sdl.int) |int| {
            switch (int) {
                .int_to_error => if (ret_val == 0) {
                    return;
                } else {
                    return CError.SdlError;
                },
                .int_to_zig => {
                    return @as(RetType, ret_val);
                },
            }
        } else {
            return ret_val;
        },
        .Optional => if (options.sdl.optional_to_error) {
            if (ret_val) |val| {
                return val;
            } else {
                return CError.SdlError;
            }
        } else {
            return ret_val;
        },
        .Pointer => |pointer| switch (pointer.size) {
            .C => if (options.sdl.many_ptr_to_single) {
                if (ret_val != 0) {
                    return @ptrCast(*pointer.child, ret_val);
                } else {
                    return CError.SdlError;
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
    switch (options) {
        .sdl => {
            switch (@typeInfo(@TypeOf(ret_val))) {
                .ErrorUnion => if (std.meta.isError(ret_val)) {
                    std.log.err("{s}", .{c.SDL_GetError()});
                },
                else => {},
            }
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
            if (func_info.args.len == 0) {
                return (struct {
                    fn f() RetType {
                        return wrapPrintError(options, wrapReturn(func(), options));
                    }
                }).f;
            } else {
                return (struct {
                    fn f(args: anytype) RetType {
                        return wrapPrintError(options, wrapReturn(@call(.{}, func, args), options));
                    }
                }).f;
            }
        },
        else => @compileError("Can't wrap a non-function"),
    }
}
