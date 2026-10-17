const std = @import("std");

test "module compiles" {
    std.testing.refAllDecls(@This());
}
