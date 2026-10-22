const std = @import("std");
const DecodeError = @import("errors.zig").DecodeError;
const int = @import("int.zig");
const SliceReader = @import("reader.zig").SliceReader;
const SliceWriter = @import("writer.zig").SliceWriter;
const ListWriter = @import("writer.zig").ListWriter;

pub const MAX_SIZE: u64 = 0x02000000;

pub fn compactSizeLen(n: u64) u4 {
    if (n < 253) return 1;
    if (n <= 0xffff) return 3;
    if (n <= 0xffffffff) return 5;
    return 9;
}

pub fn writeCompactSize(w: anytype, n: u64) !void {
    if (n < 253) {
        try int.writeInt(u8, w, @intCast(n));
    } else if (n <= 0xffff) {
        try int.writeInt(u8, w, 253);
        try int.writeInt(u16, w, @intCast(n));
    } else if (n <= 0xffffffff) {
        try int.writeInt(u8, w, 254);
        try int.writeInt(u32, w, @intCast(n));
    } else {
        try int.writeInt(u8, w, 255);
        try int.writeInt(u64, w, n);
    }
}

pub fn readCompactSize(r: anytype) DecodeError!u64 {
    return readCompactSizeOpts(r, true);
}

/// The canonical check runs before the MAX_SIZE check, matching Core's error order.
pub fn readCompactSizeOpts(r: anytype, range_check: bool) DecodeError!u64 {
    const tag = try int.readInt(u8, r);
    const n: u64 = switch (tag) {
        0...252 => tag,
        253 => try readAtLeast(u16, r, 253),
        254 => try readAtLeast(u32, r, 0x10000),
        255 => try readAtLeast(u64, r, 0x100000000),
    };
    if (range_check and n > MAX_SIZE) return error.SizeTooLarge;
    return n;
}

fn readAtLeast(comptime T: type, r: anytype, min: u64) DecodeError!u64 {
    const n = try int.readInt(T, r);
    if (n < min) return error.NonCanonicalCompactSize;
    return n;
}

pub fn readCompactSizeAs(comptime T: type, r: anytype, range_check: bool) DecodeError!T {
    const n = try readCompactSizeOpts(r, range_check);
    return std.math.cast(T, n) orelse error.ValueOutOfRange;
}

const boundaries = [_]struct { value: u64, encoding: []const u8 }{
    .{ .value = 0, .encoding = &.{0x00} },
    .{ .value = 0xfc, .encoding = &.{0xfc} },
    .{ .value = 0xfd, .encoding = &.{ 0xfd, 0xfd, 0x00 } },
    .{ .value = 0xffff, .encoding = &.{ 0xfd, 0xff, 0xff } },
    .{ .value = 0x10000, .encoding = &.{ 0xfe, 0x00, 0x00, 0x01, 0x00 } },
    .{ .value = MAX_SIZE, .encoding = &.{ 0xfe, 0x00, 0x00, 0x00, 0x02 } },
    .{ .value = 0xffffffff, .encoding = &.{ 0xfe, 0xff, 0xff, 0xff, 0xff } },
    .{ .value = 0x100000000, .encoding = &.{ 0xff, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00 } },
    .{ .value = std.math.maxInt(u64), .encoding = &.{ 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff } },
};

test "boundary values encode and decode" {
    for (boundaries) |case| {
        var buf: [9]u8 = undefined;
        var w: SliceWriter = .init(&buf);
        try writeCompactSize(&w, case.value);
        try std.testing.expectEqualSlices(u8, case.encoding, w.written());
        try std.testing.expectEqual(case.encoding.len, compactSizeLen(case.value));
        var r: SliceReader = .init(case.encoding);
        try std.testing.expectEqual(case.value, try readCompactSizeOpts(&r, false));
        try std.testing.expect(r.isEmpty());
    }
}

test "compactsize" {
    var w: ListWriter = .init(std.testing.allocator);
    defer w.deinit();
    var i: u64 = 1;
    while (i <= MAX_SIZE) : (i *= 2) {
        try writeCompactSize(&w, i - 1);
        try writeCompactSize(&w, i);
    }
    var r: SliceReader = .init(w.written());
    i = 1;
    while (i <= MAX_SIZE) : (i *= 2) {
        try std.testing.expectEqual(i - 1, try readCompactSize(&r));
        try std.testing.expectEqual(i, try readCompactSize(&r));
    }
    try std.testing.expect(r.isEmpty());
}

test "noncanonical" {
    const rejected = [_][]const u8{
        &.{ 0xfd, 0x00, 0x00 },
        &.{ 0xfd, 0xfc, 0x00 },
        &.{ 0xfe, 0x00, 0x00, 0x00, 0x00 },
        &.{ 0xfe, 0xff, 0xff, 0x00, 0x00 },
        &.{ 0xff, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 },
        &.{ 0xff, 0xff, 0xff, 0xff, 0x01, 0x00, 0x00, 0x00, 0x00 },
    };
    for (rejected) |encoding| {
        var r: SliceReader = .init(encoding);
        try std.testing.expectError(error.NonCanonicalCompactSize, readCompactSize(&r));
    }
    var r: SliceReader = .init(&.{ 0xfd, 0xfd, 0x00 });
    try std.testing.expectEqual(253, try readCompactSize(&r));
}

test "MAX_SIZE is enforced only with range checking" {
    var r: SliceReader = .init(&.{ 0xfe, 0x00, 0x00, 0x00, 0x02 });
    try std.testing.expectEqual(MAX_SIZE, try readCompactSize(&r));
    const too_large = [_]u8{ 0xfe, 0x01, 0x00, 0x00, 0x02 };
    r = .init(&too_large);
    try std.testing.expectError(error.SizeTooLarge, readCompactSize(&r));
    r = .init(&too_large);
    try std.testing.expectEqual(MAX_SIZE + 1, try readCompactSizeOpts(&r, false));
}

test "non-canonical is reported before too large" {
    var r: SliceReader = .init(&.{ 0xff, 0x00, 0x00, 0x00, 0x03, 0x00, 0x00, 0x00, 0x00 });
    try std.testing.expectError(error.NonCanonicalCompactSize, readCompactSize(&r));
}

test "truncated input fails" {
    for (boundaries) |case| {
        for (0..case.encoding.len) |len| {
            var r: SliceReader = .init(case.encoding[0..len]);
            try std.testing.expectError(error.EndOfStream, readCompactSizeOpts(&r, false));
        }
    }
}

test "value must fit the destination type" {
    var r: SliceReader = .init(&.{ 0xfd, 0x00, 0x01 });
    try std.testing.expectError(error.ValueOutOfRange, readCompactSizeAs(u8, &r, true));
    r = .init(&.{ 0xfd, 0x00, 0x01 });
    try std.testing.expectEqual(256, try readCompactSizeAs(u16, &r, true));
}
