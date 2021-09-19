const std = @import("std");
const builtin = std.builtin;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const Console = @import("console.zig").Console;
const ines = @import("ines.zig");

const MapperInitFn = fn (*Allocator, *Console, *ines.RomInfo) Allocator.Error!GenericMapper;

pub const GenericMapper = struct {
    mapper_ptr: OpaquePtr,

    mapper_readPrg: fn (GenericMapper, u16) u8,
    mapper_readChr: fn (GenericMapper, u16) u8,

    mapper_writePrg: fn (*GenericMapper, u16, u8) void,
    mapper_writeChr: fn (*GenericMapper, u16, u8) void,

    mapper_deinit: fn (GenericMapper, *Allocator) void,

    const OpaquePtr = *align(@alignOf(usize)) opaque {};

    fn setup(comptime T: type) MapperInitFn {
        GenericMapper.validateMapper(T);
        return (struct {
            pub fn init(allocator: *Allocator, console: *Console, info: *ines.RomInfo) Allocator.Error!GenericMapper {
                const ptr = try allocator.create(T);
                try T.initMem(ptr, allocator, console, info);
                return GenericMapper{
                    .mapper_ptr = @ptrCast(OpaquePtr, ptr),

                    .mapper_readPrg = T.readPrg,
                    .mapper_readChr = T.readChr,

                    .mapper_writePrg = T.writePrg,
                    .mapper_writeChr = T.writeChr,

                    .mapper_deinit = T.deinitMem,
                };
            }
        }).init;
    }

    pub fn deinit(self: GenericMapper, allocator: *Allocator) void {
        self.mapper_deinit(self, allocator);
    }

    pub fn readPrg(self: GenericMapper, addr: u16) u8 {
        return self.mapper_readPrg(self, addr);
    }

    pub fn readChr(self: GenericMapper, addr: u16) u8 {
        return self.mapper_readChr(self, addr);
    }

    pub fn writePrg(self: *GenericMapper, addr: u16) void {
        self.mapper_writePrg(self, addr);
    }

    pub fn writeChr(self: *GenericMapper, addr: u16) void {
        self.mapper_writeChr(self, addr);
    }

    // I really don't need this because the type system will *probably* take care of it for me,
    // but I want to be sure nothing unexpected happens
    fn validateMapper(comptime T: type) void {
        const type_info = @typeInfo(T);

        assert(std.meta.activeTag(type_info) == @typeInfo(builtin.TypeInfo).Union.tag_type.?.Struct);

        const InitFn = @typeInfo(@TypeOf(@as(T, undefined).initMem)).BoundFn;
        const ReadPrgFn = @typeInfo(@TypeOf(@as(T, undefined).readPrg)).BoundFn;
        const ReadChrFn = @typeInfo(@TypeOf(@as(T, undefined).readChr)).BoundFn;
        const WritePrgFn = @typeInfo(@TypeOf(@as(T, undefined).writePrg)).BoundFn;
        const WriteChrFn = @typeInfo(@TypeOf(@as(T, undefined).writeChr)).BoundFn;
        const DeinitFn = @typeInfo(@TypeOf(@as(T, undefined).deinitMem)).BoundFn;

        assert(InitFn.args.len == 4);
        assert(InitFn.args[0].arg_type == *T);
        assert(InitFn.args[1].arg_type == *Allocator);
        assert(InitFn.args[2].arg_type == *Console);
        assert(InitFn.args[3].arg_type == *ines.RomInfo);
        assert(InitFn.return_type == Allocator.Error!void);

        assert(ReadPrgFn.args.len == 2);
        assert(ReadPrgFn.args[0].arg_type == GenericMapper);
        assert(ReadPrgFn.args[1].arg_type == u16);
        assert(ReadPrgFn.return_type == u8);

        assert(ReadChrFn.args.len == 2);
        assert(ReadChrFn.args[0].arg_type == GenericMapper);
        assert(ReadChrFn.args[1].arg_type == u16);
        assert(ReadChrFn.return_type == u8);

        assert(WritePrgFn.args.len == 3);
        assert(WritePrgFn.args[0].arg_type == *GenericMapper);
        assert(WritePrgFn.args[1].arg_type == u16);
        assert(WritePrgFn.args[2].arg_type == u8);
        assert(WritePrgFn.return_type == void);

        assert(WriteChrFn.args.len == 3);
        assert(WriteChrFn.args[0].arg_type == *GenericMapper);
        assert(WriteChrFn.args[1].arg_type == u16);
        assert(WriteChrFn.args[2].arg_type == u8);
        assert(WriteChrFn.return_type == void);

        assert(DeinitFn.args.len == 2);
        assert(DeinitFn.args[0].arg_type == GenericMapper);
        assert(DeinitFn.args[1].arg_type == *Allocator);
        assert(DeinitFn.return_type == void);
    }
};

const UnimplementedMapper = struct {
    dummy: u64,

    fn initMem(_: *UnimplementedMapper, _: *Allocator, _: *Console, _: *ines.RomInfo) Allocator.Error!void {
        @panic("Mapper not implemented");
    }

    fn deinitMem(_: GenericMapper, _: *Allocator) void {
        @panic("Mapper not implemented");
    }

    fn readPrg(_: GenericMapper, _: u16) u8 {
        @panic("Mapper not implemented");
    }

    fn readChr(_: GenericMapper, _: u16) u8 {
        @panic("Mapper not implemented");
    }

    fn writePrg(_: *GenericMapper, _: u16, _: u8) void {
        @panic("Mapper not implemented");
    }

    fn writeChr(_: *GenericMapper, _: u16, _: u8) void {
        @panic("Mapper not implemented");
    }
};

pub const inits: [255]MapperInitFn = blk: {
    var types = [_]type{UnimplementedMapper} ** 255;

    types[0] = @import("mapper/nrom.zig").Mapper;

    var result = [_]MapperInitFn{undefined} ** 255;
    for (types) |T, i| {
        result[i] = GenericMapper.setup(T);
    }

    break :blk result;
};
