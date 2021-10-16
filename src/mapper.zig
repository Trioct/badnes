const std = @import("std");
const builtin = std.builtin;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const build_options = @import("build_options");

const ines = @import("ines.zig");

const console_ = @import("console.zig");
const Config = console_.Config;
const Console = console_.Console;

const common = @import("mapper/common.zig");

/// Avoids recursion in GenericMapper
fn MapperInitFn(comptime config: Config) type {
    return MapperInitFnSafe(GenericMapper(config), config);
}

fn MapperInitFnSafe(comptime T: type, comptime config: Config) type {
    return fn (*Allocator, *Console(config), *ines.RomInfo) Allocator.Error!?T;
}

// Not sure exactly how I want to structure this
// currently used for debugging stuff in imgui
pub const MapperState = struct {
    prg_rom_bank_size: usize,
    prg_rom_bank_bits: u4,
    prg_rom_selected_banks: []usize,
};

pub fn GenericMapper(comptime config: Config) type {
    return struct {
        const Self = @This();

        mapper_ptr: OpaquePtr,

        deinitFn: fn (Self, *Allocator) void,

        getStateFn: if (build_options.imgui) fn (Self) MapperState else void,

        cpuCycledFn: ?(fn (*Self) void),
        mirrorNametableFn: fn (Self, u16) u12,

        readPrgFn: fn (Self, u16) ?u8,
        readChrFn: fn (Self, u16) u8,

        writePrgFn: fn (*Self, u16, u8) void,
        writeChrFn: fn (*Self, u16, u8) void,

        const OpaquePtr = *align(@alignOf(usize)) opaque {};

        fn setup(comptime T: type) MapperInitFnSafe(Self, config) {
            return (struct {
                pub fn init(
                    allocator: *Allocator,
                    console: *Console(config),
                    info: *ines.RomInfo,
                ) Allocator.Error!?Self {
                    if (@hasField(T, "dummy_is_not_implemented")) {
                        return null;
                    }

                    const getStateFn = blk: {
                        if (build_options.imgui) {
                            if (@hasDecl(T, "getState")) {
                                break :blk T.getState;
                            } else if (@hasField(T, "prgs")) {
                                break :blk common.getState(T, config, "prgs");
                            } else {
                                @compileError("Imgui needs getState function in mapper, or proper field names for default function");
                            }
                        } else {
                            break :blk undefined;
                        }
                    };

                    const ptr = try allocator.create(T);
                    try T.initMem(ptr, allocator, console, info);
                    return Self{
                        .mapper_ptr = @ptrCast(OpaquePtr, ptr),

                        .deinitFn = T.deinitMem,

                        .getStateFn = getStateFn,

                        .cpuCycledFn = if (@hasDecl(T, "cpuCycled")) T.cpuCycled else null,
                        .mirrorNametableFn = T.mirrorNametable,

                        .readPrgFn = T.readPrg,
                        .readChrFn = T.readChr,

                        .writePrgFn = T.writePrg,
                        .writeChrFn = T.writeChr,
                    };
                }
            }).init;
        }

        pub fn deinit(self: Self, allocator: *Allocator) void {
            self.deinitFn(self, allocator);
        }
    };
}

pub fn UnimplementedMapper(comptime config: Config, comptime number: u8) type {
    const G = GenericMapper(config);
    var buf = [1]u8{undefined} ** 3;
    buf[2] = '0' + (number % 10);
    buf[1] = '0' + (number % 100) / 10;
    buf[0] = '0' + number / 100;
    const msg = "Mapper " ++ buf ++ " not implemented";
    return struct {
        dummy_is_not_implemented: u64,

        fn initMem(_: *@This(), _: *Allocator, _: *Console(config), _: *ines.RomInfo) Allocator.Error!void {
            @panic(msg);
        }

        fn deinitMem(_: G, _: *Allocator) void {
            @panic(msg);
        }

        fn mirrorNametable(_: G, _: u16) u12 {
            @panic(msg);
        }

        fn readPrg(_: G, _: u16) ?u8 {
            @panic(msg);
        }

        fn readChr(_: G, _: u16) u8 {
            @panic(msg);
        }

        fn writePrg(_: *G, _: u16, _: u8) void {
            @panic(msg);
        }

        fn writeChr(_: *G, _: u16, _: u8) void {
            @panic(msg);
        }
    };
}

pub fn inits(comptime config: Config) [255]MapperInitFn(config) {
    @setEvalBranchQuota(2000);
    var types = [_]?type{null} ** 255;

    types[0] = @import("mapper/nrom.zig").Mapper(config);
    types[1] = @import("mapper/mmc1.zig").Mapper(config);
    types[2] = @import("mapper/uxrom.zig").Mapper(config);
    types[4] = @import("mapper/mmc3.zig").Mapper(config);

    var result = [_]MapperInitFn(config){undefined} ** 255;
    for (types) |To, i| {
        if (To) |T| {
            result[i] = GenericMapper(config).setup(T);
        } else {
            result[i] = GenericMapper(config).setup(UnimplementedMapper(config, i));
        }
    }

    return result;
}
