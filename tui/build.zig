const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Get dependencies
    const vaxis_dep = b.dependency("vaxis", .{
        .target = target,
        .optimize = optimize,
    });
    const yaml_dep = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });

    // Create root module with imports
    const root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "vaxis", .module = vaxis_dep.module("vaxis") },
            .{ .name = "yaml", .module = yaml_dep.module("yaml") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "masque-draft",
        .root_module = root_module,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run masque-draft TUI");
    run_step.dependOn(&run_cmd.step);
}
