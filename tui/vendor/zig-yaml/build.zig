const std = @import("std");

// Vendored, trimmed build.zig for zig-yaml 0.3.0 (Zig 0.16 compatible).
// Upstream main's build.zig @imports test/spec.zig, which was not migrated to
// Zig 0.16 (uses removed std.fs.cwd()/std.StringArrayHashMap) and fails to
// compile even though the spec tests are gated behind a default-false option.
// We only consume the `yaml` module, so the test/example/spec wiring is dropped.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const yaml_module = b.addModule("yaml", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
    });

    const yaml_tests = b.addTest(.{
        .root_module = yaml_module,
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(yaml_tests).step);
}
