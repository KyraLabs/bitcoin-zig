const std = @import("std");
const DecodeError = @import("errors.zig").DecodeError;
const SliceReader = @import("reader.zig").SliceReader;
const SliceWriter = @import("writer.zig").SliceWriter;
const CountingWriter = @import("writer.zig").CountingWriter;

fn assertWireInt(comptime T: type) void {
    switch (T) {
        u8, i8, u16, i16, u32, i32, u64, i64 => {},
        else => @compileError("not a wire integer type: " ++ @typeName(T)),
    }
}

pub fn readInt(comptime T: type, r: anytype) DecodeError!T {
    assertWireInt(T);
    var b: [@sizeOf(T)]u8 = undefined;
    try r.readSlice(&b);
    return std.mem.readInt(T, &b, .little);
}

pub fn writeInt(comptime T: type, w: anytype, v: T) !void {
    assertWireInt(T);
    var b: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &b, v, .little);
    try w.writeSlice(&b);
}

pub fn readU16Be(r: anytype) DecodeError!u16 {
    var b: [2]u8 = undefined;
    try r.readSlice(&b);
    return std.mem.readInt(u16, &b, .big);
}

pub fn writeU16Be(w: anytype, v: u16) !void {
    var b: [2]u8 = undefined;
    std.mem.writeInt(u16, &b, v, .big);
    try w.writeSlice(&b);
}

/// Any non-zero byte reads as true, as in Core.
pub fn readBool(r: anytype) DecodeError!bool {
    return try readInt(u8, r) != 0;
}

pub fn writeBool(w: anytype, v: bool) !void {
    try writeInt(u8, w, @intFromBool(v));
}

pub fn readArray(comptime N: usize, r: anytype) DecodeError![N]u8 {
    var a: [N]u8 = undefined;
    try r.readSlice(&a);
    return a;
}

pub fn writeArray(comptime N: usize, w: anytype, a: *const [N]u8) !void {
    try w.writeSlice(a);
}

fn expectEncoding(comptime T: type, v: T, expected: []const u8) !void {
    var buf: [8]u8 = undefined;
    var w: SliceWriter = .init(&buf);
    try writeInt(T, &w, v);
    try std.testing.expectEqualSlices(u8, expected, w.written());
    var r: SliceReader = .init(expected);
    try std.testing.expectEqual(v, try readInt(T, &r));
    try std.testing.expect(r.isEmpty());
}

test "integers encode little-endian" {
    try expectEncoding(u8, 0xab, &.{0xab});
    try expectEncoding(i8, -1, &.{0xff});
    try expectEncoding(u16, 0x0102, &.{ 0x02, 0x01 });
    try expectEncoding(i16, -2, &.{ 0xfe, 0xff });
    try expectEncoding(u32, 1, &.{ 0x01, 0x00, 0x00, 0x00 });
    try expectEncoding(i32, -1, &.{ 0xff, 0xff, 0xff, 0xff });
    try expectEncoding(u64, 0x0102030405060708, &.{ 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01 });
    try expectEncoding(i64, -1, &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff });
}

test "signed extremes round-trip" {
    try expectEncoding(i32, std.math.minInt(i32), &.{ 0x00, 0x00, 0x00, 0x80 });
    try expectEncoding(i32, std.math.maxInt(i32), &.{ 0xff, 0xff, 0xff, 0x7f });
    try expectEncoding(i64, std.math.minInt(i64), &.{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80 });
    try expectEncoding(i64, std.math.maxInt(i64), &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x7f });
}

test "port encodes big-endian" {
    var buf: [2]u8 = undefined;
    var w: SliceWriter = .init(&buf);
    try writeU16Be(&w, 8333);
    try std.testing.expectEqualSlices(u8, &.{ 0x20, 0x8d }, w.written());
    var r: SliceReader = .init(&.{ 0x20, 0x8d });
    try std.testing.expectEqual(8333, try readU16Be(&r));
}

test "bool writes 0 or 1 and reads any non-zero as true" {
    var buf: [2]u8 = undefined;
    var w: SliceWriter = .init(&buf);
    try writeBool(&w, false);
    try writeBool(&w, true);
    try std.testing.expectEqualSlices(u8, &.{ 0x00, 0x01 }, w.written());
    var r: SliceReader = .init(&.{ 0x00, 0x01, 0x02 });
    try std.testing.expectEqual(false, try readBool(&r));
    try std.testing.expectEqual(true, try readBool(&r));
    try std.testing.expectEqual(true, try readBool(&r));
}

test "array round-trips with no prefix" {
    var a: [32]u8 = undefined;
    for (&a, 0..) |*byte, i| byte.* = @intCast(i);
    var buf: [32]u8 = undefined;
    var w: SliceWriter = .init(&buf);
    try writeArray(32, &w, &a);
    try std.testing.expectEqualSlices(u8, &a, w.written());
    var r: SliceReader = .init(w.written());
    try std.testing.expectEqual(a, try readArray(32, &r));
    try std.testing.expect(r.isEmpty());
}

test "sizes" {
    var w: CountingWriter = .{};
    try writeInt(i8, &w, 0);
    try std.testing.expectEqual(1, w.count);
    try writeInt(u8, &w, 0);
    try std.testing.expectEqual(2, w.count);
    try writeInt(i16, &w, 0);
    try writeInt(u16, &w, 0);
    try std.testing.expectEqual(6, w.count);
    try writeInt(i32, &w, 0);
    try writeInt(u32, &w, 0);
    try std.testing.expectEqual(14, w.count);
    try writeInt(i64, &w, 0);
    try writeInt(u64, &w, 0);
    try std.testing.expectEqual(30, w.count);
    try writeBool(&w, true);
    try std.testing.expectEqual(31, w.count);
    try writeArray(1, &w, &.{0});
    try writeArray(4, &w, &.{ 0, 0, 0, 0 });
    try std.testing.expectEqual(36, w.count);
}

test "truncated input fails" {
    var r: SliceReader = .init(&.{ 0x01, 0x02, 0x03 });
    try std.testing.expectError(error.EndOfStream, readInt(u32, &r));
    try std.testing.expectError(error.EndOfStream, readArray(4, &r));
    try std.testing.expectEqual(3, r.remaining());
    var empty: SliceReader = .init(&.{});
    try std.testing.expectError(error.EndOfStream, readBool(&empty));
    try std.testing.expectError(error.EndOfStream, readU16Be(&empty));
}
