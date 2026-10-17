const std = @import("std");
const manifest = @import("build.zig.zon");

const ModuleSpec = struct {
    name: []const u8,
    deps: []const []const u8,
};

// Order matters: every module may only depend on modules listed before it.
const module_specs = [_]ModuleSpec{
    .{ .name = "util", .deps = &.{} },
    .{ .name = "test_util", .deps = &.{"util"} },
    .{ .name = "serialization", .deps = &.{"util"} },
    .{ .name = "crypto", .deps = &.{ "util", "serialization" } },
    .{ .name = "primitives", .deps = &.{ "util", "serialization", "crypto" } },
    .{ .name = "script", .deps = &.{ "util", "serialization", "crypto", "primitives" } },
    .{ .name = "consensus", .deps = &.{ "util", "serialization", "crypto", "primitives", "script" } },
    .{ .name = "storage", .deps = &.{ "util", "serialization", "crypto", "primitives", "script", "consensus" } },
    .{ .name = "validation", .deps = &.{ "util", "serialization", "crypto", "primitives", "script", "consensus", "storage" } },
    .{ .name = "mempool", .deps = &.{ "util", "serialization", "crypto", "primitives", "script", "consensus", "storage", "validation" } },
    .{ .name = "indexes", .deps = &.{ "util", "serialization", "crypto", "primitives", "consensus", "storage", "validation" } },
    .{ .name = "p2p", .deps = &.{ "util", "serialization", "crypto", "primitives", "consensus", "storage", "validation", "mempool", "indexes" } },
    .{ .name = "rpc", .deps = &.{ "util", "serialization", "crypto", "primitives", "script", "consensus", "storage", "validation", "mempool", "indexes", "p2p" } },
    .{ .name = "node", .deps = &.{ "util", "serialization", "crypto", "primitives", "script", "consensus", "storage", "validation", "mempool", "indexes", "p2p", "rpc" } },
};

comptime {
    for (module_specs, 0..) |spec, i| {
        for (spec.deps) |dep| {
            if (indexOf(dep) orelse @compileError("unknown dependency " ++ dep) >= i)
                @compileError(spec.name ++ " depends on later module " ++ dep);
        }
    }
}

fn indexOf(name: []const u8) ?usize {
    for (module_specs, 0..) |spec, i| {
        if (std.mem.eql(u8, spec.name, name)) return i;
    }
    return null;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const test_filters = b.option([]const []const u8, "test-filter", "Only run tests whose name contains this substring") orelse &.{};
    const test_module = b.option([]const u8, "test-module", "Only run the tests of this module");

    var modules: [module_specs.len]*std.Build.Module = undefined;
    for (module_specs, &modules) |spec, *module| {
        module.* = b.createModule(.{
            .root_source_file = b.path(b.fmt("src/{s}/root.zig", .{spec.name})),
            .target = target,
            .optimize = optimize,
        });
        for (spec.deps) |dep| {
            module.*.addImport(dep, modules[indexOf(dep).?]);
        }
    }

    const test_step = b.step("test", "Run unit tests");
    if (test_module) |name| {
        if (indexOf(name) == null) {
            test_step.dependOn(&b.addFail(b.fmt("unknown test module '{s}'", .{name})).step);
        }
    }
    for (module_specs, modules) |spec, module| {
        if (test_module) |name| {
            if (!std.mem.eql(u8, name, spec.name)) continue;
        }
        const unit_tests = b.addTest(.{
            .name = spec.name,
            .root_module = module,
            .filters = test_filters,
        });
        test_step.dependOn(&b.addRunArtifact(unit_tests).step);
    }

    const exe_options = b.addOptions();
    exe_options.addOption([]const u8, "version", manifest.version);

    const exe = b.addExecutable(.{
        .name = "kyra",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "node", .module = modules[indexOf("node").?] },
                .{ .name = "build_options", .module = exe_options.createModule() },
            },
        }),
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run the node");
    run_step.dependOn(&run_cmd.step);

    const fmt_step = b.step("fmt", "Check source formatting");
    fmt_step.dependOn(&b.addFmt(.{
        .paths = &.{ b.path("src"), b.path("build.zig"), b.path("build.zig.zon") },
        .check = true,
    }).step);
}
