const std = @import("std");
const builtin = std.builtin;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const ines = @import("ines.zig");

const console_ = @import("console.zig");
const Config = console_.Config;
const Console = console_.Console;

/// Avoids recursion in GenericMapper
fn MapperInitFn(comptime config: Config) type {
    return MapperInitFnSafe(GenericMapper(config), config);
}

fn MapperInitFnSafe(comptime T: type, comptime config: Config) type {
    return fn (*Allocator, *Console(config), *ines.RomInfo) Allocator.Error!T;
}

pub fn GenericMapper(comptime config: Config) type {
    return struct {
        const Self = @This();

        mapper_ptr: OpaquePtr,

        mapper_mirrorNametable: fn (Self, u16) u12,

        mapper_readPrg: fn (Self, u16) u8,
        mapper_readChr: fn (Self, u16) u8,

        mapper_writePrg: fn (*Self, u16, u8) void,
        mapper_writeChr: fn (*Self, u16, u8) void,

        mapper_deinit: fn (Self, *Allocator) void,

        const OpaquePtr = *align(@alignOf(usize)) opaque {};

        fn setup(comptime T: type) MapperInitFnSafe(Self, config) {
            //Self.validateMapper(T);
            return (struct {
                pub fn init(
                    allocator: *Allocator,
                    console: *Console(config),
                    info: *ines.RomInfo,
                ) Allocator.Error!Self {
                    const ptr = try allocator.create(T);
                    try T.initMem(ptr, allocator, console, info);
                    return Self{
                        .mapper_ptr = @ptrCast(OpaquePtr, ptr),

                        .mapper_mirrorNametable = T.mirrorNametable,

                        .mapper_readPrg = T.readPrg,
                        .mapper_readChr = T.readChr,

                        .mapper_writePrg = T.writePrg,
                        .mapper_writeChr = T.writeChr,

                        .mapper_deinit = T.deinitMem,
                    };
                }
            }).init;
        }

        pub fn deinit(self: Self, allocator: *Allocator) void {
            self.mapper_deinit(self, allocator);
        }

        pub fn mirrorNametable(self: Self, addr: u16) u12 {
            return self.mapper_mirrorNametable(self, addr);
        }

        pub fn readPrg(self: Self, addr: u16) u8 {
            return self.mapper_readPrg(self, addr);
        }

        pub fn readChr(self: Self, addr: u16) u8 {
            return self.mapper_readChr(self, addr);
        }

        pub fn writePrg(self: *Self, addr: u16) void {
            self.mapper_writePrg(self, addr);
        }

        pub fn writeChr(self: *Self, addr: u16) void {
            self.mapper_writeChr(self, addr);
        }

        // I really don't need this because the type system will *probably* take care of it for me,
        // but I want to be sure nothing unexpected happens
        fn validateMapper(comptime T: type) void {
            const type_info = @typeInfo(T);

            assert(std.meta.activeTag(type_info) == @typeInfo(builtin.TypeInfo).Union.tag_type.?.Struct);

            const InitFn = @typeInfo(@TypeOf(@as(T, undefined).initMem)).BoundFn;
            const MirrorNametableFn = @typeInfo(@TypeOf(@as(T, undefined).mirrorNametable)).BoundFn;
            const ReadPrgFn = @typeInfo(@TypeOf(@as(T, undefined).readPrg)).BoundFn;
            const ReadChrFn = @typeInfo(@TypeOf(@as(T, undefined).readChr)).BoundFn;
            const WritePrgFn = @typeInfo(@TypeOf(@as(T, undefined).writePrg)).BoundFn;
            const WriteChrFn = @typeInfo(@TypeOf(@as(T, undefined).writeChr)).BoundFn;
            const DeinitFn = @typeInfo(@TypeOf(@as(T, undefined).deinitMem)).BoundFn;

            assert(InitFn.args.len == 4);
            assert(InitFn.args[0].arg_type == *T);
            assert(InitFn.args[1].arg_type == *Allocator);
            assert(InitFn.args[2].arg_type == *Console(config));
            assert(InitFn.args[3].arg_type == *ines.RomInfo);
            assert(InitFn.return_type == Allocator.Error!void);

            assert(MirrorNametableFn.args.len == 2);
            assert(MirrorNametableFn.args[0].arg_type == Self);
            assert(MirrorNametableFn.args[1].arg_type == u16);
            assert(MirrorNametableFn.return_type == u12);

            assert(ReadPrgFn.args.len == 2);
            assert(ReadPrgFn.args[0].arg_type == Self);
            assert(ReadPrgFn.args[1].arg_type == u16);
            assert(ReadPrgFn.return_type == u8);

            assert(ReadChrFn.args.len == 2);
            assert(ReadChrFn.args[0].arg_type == Self);
            assert(ReadChrFn.args[1].arg_type == u16);
            assert(ReadChrFn.return_type == u8);

            assert(WritePrgFn.args.len == 3);
            assert(WritePrgFn.args[0].arg_type == *Self);
            assert(WritePrgFn.args[1].arg_type == u16);
            assert(WritePrgFn.args[2].arg_type == u8);
            assert(WritePrgFn.return_type == void);

            assert(WriteChrFn.args.len == 3);
            assert(WriteChrFn.args[0].arg_type == *Self);
            assert(WriteChrFn.args[1].arg_type == u16);
            assert(WriteChrFn.args[2].arg_type == u8);
            assert(WriteChrFn.return_type == void);

            assert(DeinitFn.args.len == 2);
            assert(DeinitFn.args[0].arg_type == Self);
            assert(DeinitFn.args[1].arg_type == *Allocator);
            assert(DeinitFn.return_type == void);
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
        dummy: u64,

        fn initMem(_: *@This(), _: *Allocator, _: *Console(config), _: *ines.RomInfo) Allocator.Error!void {
            @panic(msg);
        }

        fn deinitMem(_: G, _: *Allocator) void {
            @panic(msg);
        }

        fn mirrorNametable(_: G, _: u16) u12 {
            @panic(msg);
        }

        fn readPrg(_: G, _: u16) u8 {
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
