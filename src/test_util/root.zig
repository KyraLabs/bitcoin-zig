const std = @import("std");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub const core_test_data = build_options.core_test_data;
pub const allow_missing_core_test_data = build_options.allow_missing_core_test_data;

const max_vector_size = 16 * 1024 * 1024;

pub const MissingDataPolicy = enum { fail, skip };

/// Reads a file from the Core test data directory. Caller owns the result.
pub fn readVector(allocator: Allocator, name: []const u8) ![]u8 {
    return readVectorFrom(allocator, std.testing.io, .cwd(), core_test_data, name);
}

/// Like `readVector`, but an absent data directory skips the test when the
/// local opt-in is enabled.
pub fn requireVector(allocator: Allocator, name: []const u8) ![]u8 {
    return requireVectorFrom(allocator, std.testing.io, .cwd(), core_test_data, name, missingDataPolicy());
}

/// Caller must call `deinit` on the result.
pub fn requireJsonVector(allocator: Allocator, name: []const u8) !std.json.Parsed(std.json.Value) {
    return requireJsonVectorFrom(allocator, std.testing.io, .cwd(), core_test_data, name, missingDataPolicy());
}

fn missingDataPolicy() MissingDataPolicy {
    return if (allow_missing_core_test_data) .skip else .fail;
}

fn readVectorFrom(allocator: Allocator, io: Io, root: Io.Dir, data_path: []const u8, name: []const u8) ![]u8 {
    var dir = root.openDir(io, data_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return error.CoreTestDataMissing,
        else => return err,
    };
    defer dir.close(io);
    return dir.readFileAlloc(io, name, allocator, .limited(max_vector_size));
}

fn requireVectorFrom(
    allocator: Allocator,
    io: Io,
    root: Io.Dir,
    data_path: []const u8,
    name: []const u8,
    policy: MissingDataPolicy,
) ![]u8 {
    return readVectorFrom(allocator, io, root, data_path, name) catch |err| switch (err) {
        error.CoreTestDataMissing => switch (policy) {
            .fail => err,
            .skip => error.SkipZigTest,
        },
        else => err,
    };
}

fn requireJsonVectorFrom(
    allocator: Allocator,
    io: Io,
    root: Io.Dir,
    data_path: []const u8,
    name: []const u8,
    policy: MissingDataPolicy,
) !std.json.Parsed(std.json.Value) {
    const bytes = try requireVectorFrom(allocator, io, root, data_path, name, policy);
    defer allocator.free(bytes);
    return std.json.parseFromSlice(std.json.Value, allocator, bytes, .{ .allocate = .alloc_always });
}

test "siphash.json loads and parses" {
    const parsed = try requireJsonVector(std.testing.allocator, "siphash.json");
    defer parsed.deinit();
    try std.testing.expect(parsed.value == .array);
    try std.testing.expect(parsed.value.array.items.len > 0);
}

test "absent data directory fails by default" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.expectError(
        error.CoreTestDataMissing,
        requireVectorFrom(std.testing.allocator, std.testing.io, tmp.dir, "absent", "siphash.json", .fail),
    );
}

test "absent data directory skips with explicit opt-in" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try std.testing.expectError(
        error.SkipZigTest,
        requireVectorFrom(std.testing.allocator, std.testing.io, tmp.dir, "absent", "siphash.json", .skip),
    );
}

test "missing file fails even with opt-in" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, "data", .default_dir);
    try std.testing.expectError(
        error.FileNotFound,
        requireVectorFrom(std.testing.allocator, std.testing.io, tmp.dir, "data", "siphash.json", .skip),
    );
}

test "malformed json fails even with opt-in" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDir(std.testing.io, "data", .default_dir);
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "data/bad.json", .data = "[1, 2" });
    try std.testing.expectError(
        error.UnexpectedEndOfInput,
        requireJsonVectorFrom(std.testing.allocator, std.testing.io, tmp.dir, "data", "bad.json", .skip),
    );
}
