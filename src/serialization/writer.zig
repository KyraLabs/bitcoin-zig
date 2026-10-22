const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ListWriter = struct {
    allocator: Allocator,
    list: std.ArrayList(u8) = .empty,

    pub const Error = Allocator.Error;

    pub fn init(allocator: Allocator) ListWriter {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *ListWriter) void {
        self.list.deinit(self.allocator);
    }

    pub fn writeSlice(self: *ListWriter, src: []const u8) Error!void {
        try self.list.appendSlice(self.allocator, src);
    }

    pub fn written(self: ListWriter) []const u8 {
        return self.list.items;
    }

    pub fn toOwnedSlice(self: *ListWriter) Error![]u8 {
        return self.list.toOwnedSlice(self.allocator);
    }
};

/// A write that does not fit writes nothing.
pub const SliceWriter = struct {
    buf: []u8,
    pos: usize = 0,

    pub const Error = error{NoSpaceLeft};

    pub fn init(buf: []u8) SliceWriter {
        return .{ .buf = buf };
    }

    pub fn writeSlice(self: *SliceWriter, src: []const u8) Error!void {
        if (src.len > self.buf.len - self.pos) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos..][0..src.len], src);
        self.pos += src.len;
    }

    pub fn written(self: SliceWriter) []const u8 {
        return self.buf[0..self.pos];
    }
};

pub const CountingWriter = struct {
    count: u64 = 0,

    pub const Error = error{};

    pub fn writeSlice(self: *CountingWriter, src: []const u8) Error!void {
        self.count += src.len;
    }
};

test "ListWriter concatenates writes" {
    var w: ListWriter = .init(std.testing.allocator);
    defer w.deinit();
    try w.writeSlice(&.{1});
    try w.writeSlice(&.{ 2, 3 });
    try w.writeSlice(&.{ 4, 5, 6 });
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6 }, w.written());
}

test "ListWriter hands over ownership" {
    var w: ListWriter = .init(std.testing.allocator);
    defer w.deinit();
    try w.writeSlice(&.{ 1, 2 });
    const owned = try w.toOwnedSlice();
    defer std.testing.allocator.free(owned);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, owned);
    try std.testing.expectEqual(0, w.written().len);
}

test "ListWriter propagates allocation failure" {
    var w: ListWriter = .init(std.testing.failing_allocator);
    defer w.deinit();
    try std.testing.expectError(error.OutOfMemory, w.writeSlice(&.{1}));
}

test "SliceWriter concatenates writes" {
    var buf: [6]u8 = undefined;
    var w: SliceWriter = .init(&buf);
    try w.writeSlice(&.{1});
    try w.writeSlice(&.{ 2, 3 });
    try w.writeSlice(&.{ 4, 5, 6 });
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4, 5, 6 }, w.written());
}

test "SliceWriter refuses overflow without partial writes" {
    var buf: [4]u8 = .{ 0, 0, 0, 0 };
    var w: SliceWriter = .init(&buf);
    try w.writeSlice(&.{ 1, 2 });
    try std.testing.expectError(error.NoSpaceLeft, w.writeSlice(&.{ 3, 4, 5 }));
    try std.testing.expectEqualSlices(u8, &.{ 1, 2 }, w.written());
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 0, 0 }, &buf);
}

test "CountingWriter counts bytes" {
    var w: CountingWriter = .{};
    try w.writeSlice(&.{1});
    try w.writeSlice(&.{ 2, 3 });
    try w.writeSlice(&.{ 4, 5, 6 });
    try std.testing.expectEqual(6, w.count);
}
