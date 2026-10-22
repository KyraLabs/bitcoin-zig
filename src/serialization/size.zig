const std = @import("std");
const CountingWriter = @import("writer.zig").CountingWriter;
const ListWriter = @import("writer.zig").ListWriter;
const int = @import("int.zig");
const compact_size = @import("compact_size.zig");

pub fn serializedSize(value: anytype, comptime serializeFn: anytype) u64 {
    var w: CountingWriter = .{};
    serializeFn(value, &w) catch |err| switch (err) {};
    return w.count;
}

const Sample = struct {
    version: i32,
    flag: bool,
    lengths: []const u64,
    port: u16,

    fn serialize(self: *const Sample, w: anytype) !void {
        try int.writeInt(i32, w, self.version);
        try int.writeBool(w, self.flag);
        try compact_size.writeCompactSize(w, self.lengths.len);
        for (self.lengths) |n| try compact_size.writeCompactSize(w, n);
        try int.writeU16Be(w, self.port);
    }
};

test "serializedSize matches the written length" {
    const sample: Sample = .{
        .version = -1,
        .flag = true,
        .lengths = &.{ 0, 0xfc, 0xfd, 0x10000, 0x100000000 },
        .port = 8333,
    };
    var w: ListWriter = .init(std.testing.allocator);
    defer w.deinit();
    try sample.serialize(&w);
    try std.testing.expectEqual(w.written().len, serializedSize(&sample, Sample.serialize));
    try std.testing.expectEqual(4 + 1 + 1 + (1 + 1 + 3 + 5 + 9) + 2, serializedSize(&sample, Sample.serialize));
}
