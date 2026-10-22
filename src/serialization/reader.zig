const std = @import("std");
const DecodeError = @import("errors.zig").DecodeError;

/// A failed read or skip consumes no input.
pub const SliceReader = struct {
    buf: []const u8,
    pos: usize = 0,

    pub fn init(buf: []const u8) SliceReader {
        return .{ .buf = buf };
    }

    pub fn readSlice(self: *SliceReader, dst: []u8) DecodeError!void {
        if (dst.len > self.remaining()) return error.EndOfStream;
        @memcpy(dst, self.buf[self.pos..][0..dst.len]);
        self.pos += dst.len;
    }

    pub fn skip(self: *SliceReader, n: usize) DecodeError!void {
        if (n > self.remaining()) return error.EndOfStream;
        self.pos += n;
    }

    pub fn remaining(self: SliceReader) usize {
        return self.buf.len - self.pos;
    }

    pub fn isEmpty(self: SliceReader) bool {
        return self.pos == self.buf.len;
    }
};

test "reads consume input in order" {
    var r: SliceReader = .init(&.{ 1, 2, 3, 4, 5 });
    var a: [2]u8 = undefined;
    var b: [3]u8 = undefined;
    try r.readSlice(&a);
    try r.readSlice(&b);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, &a);
    try std.testing.expectEqualSlices(u8, &.{ 3, 4, 5 }, &b);
    try std.testing.expect(r.isEmpty());
}

test "read past the end fails without consuming input" {
    var r: SliceReader = .init(&.{ 1, 2, 3 });
    try r.skip(1);
    var dst: [3]u8 = undefined;
    try std.testing.expectError(error.EndOfStream, r.readSlice(&dst));
    try std.testing.expectEqual(1, r.pos);
    try std.testing.expectEqual(2, r.remaining());
}

test "zero-length read succeeds at the end" {
    var r: SliceReader = .init(&.{});
    try r.readSlice(&.{});
    try std.testing.expect(r.isEmpty());
}

test "skip past the end fails without consuming input" {
    var r: SliceReader = .init(&.{ 1, 2 });
    try std.testing.expectError(error.EndOfStream, r.skip(3));
    try std.testing.expectEqual(0, r.pos);
    try r.skip(2);
    try std.testing.expect(r.isEmpty());
}
