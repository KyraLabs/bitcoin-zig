const std = @import("std");

pub const DecodeError = @import("errors.zig").DecodeError;
pub const SliceReader = @import("reader.zig").SliceReader;
pub const ListWriter = @import("writer.zig").ListWriter;
pub const SliceWriter = @import("writer.zig").SliceWriter;
pub const CountingWriter = @import("writer.zig").CountingWriter;

const int = @import("int.zig");
pub const readInt = int.readInt;
pub const writeInt = int.writeInt;
pub const readU16Be = int.readU16Be;
pub const writeU16Be = int.writeU16Be;
pub const readBool = int.readBool;
pub const writeBool = int.writeBool;
pub const readArray = int.readArray;
pub const writeArray = int.writeArray;

const compact_size = @import("compact_size.zig");
pub const MAX_SIZE = compact_size.MAX_SIZE;
pub const compactSizeLen = compact_size.compactSizeLen;
pub const writeCompactSize = compact_size.writeCompactSize;
pub const readCompactSize = compact_size.readCompactSize;
pub const readCompactSizeOpts = compact_size.readCompactSizeOpts;
pub const readCompactSizeAs = compact_size.readCompactSizeAs;

pub const serializedSize = @import("size.zig").serializedSize;

test {
    _ = @import("reader.zig");
    _ = @import("writer.zig");
    _ = int;
    _ = compact_size;
    _ = @import("size.zig");
}
