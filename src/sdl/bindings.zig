const std = @import("std");
pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
    @cInclude("SDL2/SDL_audio.h");
});

pub const Window = c.SDL_Window;
pub const Renderer = c.SDL_Renderer;
pub const Texture = c.SDL_Texture;

pub const init = wrap(c.SDL_Init);
pub const quit = wrap(c.SDL_Quit);

pub const createWindow = wrap(c.SDL_CreateWindow);
pub const createRenderer = wrap(c.SDL_CreateRenderer);
pub const destroyWindow = wrap(c.SDL_DestroyWindow);
pub const destroyRenderer = wrap(c.SDL_DestroyRenderer);

pub const pollEvent = wrapWithOptions(c.SDL_PollEvent, .{ .int = .int_to_zig });
pub const getKeyboardState = wrapWithOptions(c.SDL_GetKeyboardState, .{
    .many_ptr_to_single = false,
});

pub const createTexture = wrap(c.SDL_CreateTexture);
pub const destroyTexture = wrap(c.SDL_DestroyTexture);
pub const lockTexture = wrap(c.SDL_LockTexture);
pub const unlockTexture = wrap(c.SDL_UnlockTexture);
pub const renderCopy = wrap(c.SDL_RenderCopy);
pub const renderPresent = wrap(c.SDL_RenderPresent);

pub const openAudioDevice = wrapWithOptions(c.SDL_OpenAudioDevice, .{ .int = null });
pub const closeAudioDevice = wrap(c.SDL_CloseAudioDevice);
pub const pauseAudioDevice = wrap(c.SDL_PauseAudioDevice);

pub const SdlError = error{
    Error,
};

const WrapOptions = struct {
    int: ?enum {
        int_to_error,
        int_to_zig,
    } = .int_to_error,
    optional_to_error: bool = true,
    many_ptr_to_single: bool = true,
};

fn WrappedReturn(comptime T: type, comptime options: WrapOptions) type {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .Int => if (options.int) |int| {
            switch (int) {
                .int_to_error => return SdlError!void,
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
        .Optional => |optional| if (options.optional_to_error) {
            return SdlError!optional.child;
        } else {
            return T;
        },
        .Pointer => |pointer| switch (pointer.size) {
            .C => if (options.many_ptr_to_single) {
                return SdlError!*pointer.child;
            } else {
                return T;
            },
            else => return T,
        },
        else => return T,
    }
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
    const RetType = WrappedReturn(ReturnType(T), options);
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

fn wrapReturn(ret_val: anytype, comptime options: WrapOptions) WrappedReturn(@TypeOf(ret_val), options) {
    const T = @TypeOf(ret_val);
    const RetType = WrappedReturn(T, options);
    const type_info = @typeInfo(@TypeOf(ret_val));
    switch (type_info) {
        .Int => if (options.int) |int| {
            switch (int) {
                .int_to_error => if (ret_val == 0) {
                    return;
                } else {
                    return SdlError.Error;
                },
                .int_to_zig => {
                    return @as(RetType, ret_val);
                },
            }
        } else {
            return ret_val;
        },
        .Optional => if (options.optional_to_error) {
            if (ret_val) |val| {
                return val;
            } else {
                return SdlError.Error;
            }
        } else {
            return ret_val;
        },
        .Pointer => |pointer| switch (pointer.size) {
            .C => if (options.many_ptr_to_single) {
                if (ret_val != 0) {
                    return @ptrCast(*pointer.child, ret_val);
                } else {
                    return SdlError.Error;
                }
            } else {
                return ret_val;
            },
            else => return ret_val,
        },
        else => return ret_val,
    }
}

fn wrapPrintError(ret_val: anytype) @TypeOf(ret_val) {
    switch (@typeInfo(@TypeOf(ret_val))) {
        .ErrorUnion => if (std.meta.isError(ret_val)) {
            std.log.err("{s}", .{c.SDL_GetError()});
        },
        else => {},
    }
    return ret_val;
}

fn wrap(comptime sdl_func: anytype) WrappedSignature(@TypeOf(sdl_func), .{}) {
    return wrapWithOptions(sdl_func, .{});
}

fn wrapWithOptions(
    comptime sdl_func: anytype,
    comptime options: WrapOptions,
) WrappedSignature(@TypeOf(sdl_func), options) {
    const T = @TypeOf(sdl_func);
    const RetType = WrappedReturn(ReturnType(T), options);
    switch (@typeInfo(@TypeOf(sdl_func))) {
        .Fn => |func_info| {
            if (func_info.args.len == 0) {
                return (struct {
                    fn f() RetType {
                        return wrapPrintError(wrapReturn(sdl_func(), options));
                    }
                }).f;
            } else {
                return (struct {
                    fn f(args: anytype) RetType {
                        return wrapPrintError(wrapReturn(@call(.{}, sdl_func, args), options));
                    }
                }).f;
            }
        },
        else => @compileError("Can't wrap a non-function"),
    }
}
