const std = @import("std");

pub const c = @cImport({
    @cInclude("SDL2/SDL.h");
});

const SdlError = error{
    Error,
};

const WrapOptions = struct {
    int: ?enum {
        IntToError,
        IntToZig,
    } = .IntToError,
    optional_to_error: bool = true,
    many_ptr_to_single: bool = true,
};

fn WrappedReturn(comptime T: type, comptime options: WrapOptions) type {
    const type_info = @typeInfo(T);
    switch (type_info) {
        .Int => if (options.int) |int| {
            switch (int) {
                .IntToError => return SdlError!void,
                .IntToZig => if (T == c_int) {
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
                .IntToError => if (ret_val == 0) {
                    return;
                } else {
                    return SdlError.Error;
                },
                .IntToZig => {
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

pub const init = wrap(c.SDL_Init);
pub const quit = wrap(c.SDL_Quit);

pub const createWindow = wrap(c.SDL_CreateWindow);
pub const createRenderer = wrap(c.SDL_CreateRenderer);
pub const destroyWindow = wrap(c.SDL_DestroyWindow);
pub const destroyRenderer = wrap(c.SDL_DestroyRenderer);

pub const pollEvent = wrapWithOptions(c.SDL_PollEvent, .{ .int = .IntToZig });
pub const getKeyboardState = wrapWithOptions(c.SDL_GetKeyboardState, .{
    .many_ptr_to_single = false,
});

pub const createTexture = wrap(c.SDL_CreateTexture);
pub const destroyTexture = wrap(c.SDL_DestroyTexture);
pub const lockTexture = wrap(c.SDL_LockTexture);
pub const unlockTexture = wrap(c.SDL_UnlockTexture);
pub const renderCopy = wrap(c.SDL_RenderCopy);
pub const renderPresent = wrap(c.SDL_RenderPresent);

pub const SdlContext = struct {
    window: *c.SDL_Window,
    renderer: *c.SDL_Renderer,
    frame_buffer: FrameBuffer,

    pub fn init(title: [:0]const u8, x: u31, y: u31, w: u31, h: u31) !SdlContext {
        const window = try createWindow(.{
            title,
            @as(c_int, x),
            @as(c_int, y),
            @as(c_int, w),
            @as(c_int, h),
            c.SDL_WINDOW_SHOWN,
        });
        errdefer destroyWindow(.{window});

        const renderer = try createRenderer(.{ window, -1, c.SDL_RENDERER_ACCELERATED });

        return SdlContext{
            .window = window,
            .renderer = renderer,
            .frame_buffer = try FrameBuffer.init(renderer, 256, 240),
        };
    }

    pub fn deinit(self: SdlContext) void {
        self.frame_buffer.deinit();
        destroyRenderer(.{self.renderer});
        destroyWindow(.{self.window});
    }

    /// Lock the window's surface for direct pixel writing
    pub fn lock(self: SdlContext) !FrameBuffer {
        var surface = try getWindowSurface(.{self.window});
        try lockSurface(.{surface});
        return FrameBuffer.init(surface) orelse return SdlError.Error;
    }

    pub fn unlock(self: SdlContext) !void {
        const surface = try getWindowSurface(.{self.window});
        unlockSurface(.{surface});
        try updateWindowSurface(.{self.window});
    }
};

pub const FrameBuffer = struct {
    texture: *c.SDL_Texture,
    pixels: ?[]u32 = null,
    width: usize,
    pixel_count: usize,

    pub fn init(renderer: *c.SDL_Renderer, width: usize, height: usize) !FrameBuffer {
        const texture = try createTexture(.{
            renderer,
            c.SDL_PIXELFORMAT_RGB888, // consider RGB24?
            c.SDL_TEXTUREACCESS_STREAMING,
            @intCast(c_int, width),
            @intCast(c_int, height),
        });
        var fb =
            FrameBuffer{
            .texture = texture,
            .width = width,
            .pixel_count = width * height,
        };
        try fb.lock();
        return fb;
    }

    pub fn deinit(self: FrameBuffer) void {
        destroyTexture(.{self.texture});
    }

    pub fn lock(self: *FrameBuffer) !void {
        var pixels: ?*c_void = undefined;
        var pitch: c_int = undefined;
        try lockTexture(.{ self.texture, null, &pixels, &pitch });
        if (pixels) |ptr| {
            self.pixels = @ptrCast([*]u32, @alignCast(4, ptr))[0..self.pixel_count];
        }
    }

    pub fn unlock(self: FrameBuffer) void {
        unlockTexture(.{self.texture});
    }

    pub fn putPixel(self: FrameBuffer, x: usize, y: usize, pixel: u32) void {
        if (self.pixels) |pixels| {
            pixels[x + y * self.width] = pixel;
        }
    }

    pub fn present(self: *FrameBuffer, renderer: *c.SDL_Renderer) !void {
        self.unlock();
        try renderCopy(.{ renderer, self.texture, null, null });
        renderPresent(.{renderer});
        try self.lock();
    }
};
