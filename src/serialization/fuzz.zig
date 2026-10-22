const std = @import("std");
const compact_size = @import("compact_size.zig");
const SliceReader = @import("reader.zig").SliceReader;
const SliceWriter = @import("writer.zig").SliceWriter;

test "fuzz CompactSize decoding" {
    try std.testing.fuzz({}, decodeCompactSize, .{});
}

test "fuzz CompactSize round-trip" {
    try std.testing.fuzz({}, roundTripCompactSize, .{});
}

fn decodeCompactSize(_: void, smith: *std.testing.Smith) !void {
    var input: [16]u8 = undefined;
    const len = smith.slice(&input);
    for ([_]bool{ false, true }) |range_check| {
        var r: SliceReader = .init(input[0..len]);
        const n = compact_size.readCompactSizeOpts(&r, range_check) catch continue;
        var buf: [9]u8 = undefined;
        var w: SliceWriter = .init(&buf);
        try compact_size.writeCompactSize(&w, n);
        try std.testing.expectEqualSlices(u8, input[0..r.pos], w.written());
    }
}

fn roundTripCompactSize(_: void, smith: *std.testing.Smith) !void {
    const n = smith.value(u64);
    var buf: [9]u8 = undefined;
    var w: SliceWriter = .init(&buf);
    try compact_size.writeCompactSize(&w, n);
    try std.testing.expectEqual(compact_size.compactSizeLen(n), w.written().len);
    var r: SliceReader = .init(w.written());
    try std.testing.expectEqual(n, try compact_size.readCompactSizeOpts(&r, false));
    try std.testing.expect(r.isEmpty());
}
