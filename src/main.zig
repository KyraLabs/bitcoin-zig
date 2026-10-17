const std = @import("std");
const build_options = @import("build_options");
const node = @import("node");

comptime {
    _ = node;
}

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    try stdout.print("bitcoin-zig version v{s}\n", .{build_options.version});
    try stdout.flush();
}
