const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "snek",
        .root_module = b.createModule(.{
            .root_source_file = b.path("snek.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const check_step = b.step("check", "");
    check_step.dependOn(&exe.step);

    exe.linkLibC();
    exe.linkSystemLibrary("m");

    if (target.result.os.tag.isDarwin()) {
        exe.linkFramework("IOKit");
        exe.linkFramework("Cocoa");
    } else if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("opengl32");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("winmm");
    }

    const raylib = b.dependency("raylib", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(raylib.artifact("raylib"));

    b.installArtifact(exe);

    const game_exe = b.addRunArtifact(exe);
    const play_step = b.step("play", "");
    play_step.dependOn(&game_exe.step);

    // Benchmark executable
    const benchmark_exe = b.addExecutable(.{
        .name = "snek-benchmark",
        .root_module = b.createModule(.{
            .root_source_file = b.path("benchmark.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    b.installArtifact(benchmark_exe);

    const benchmark_run = b.addRunArtifact(benchmark_exe);
    const benchmark_step = b.step("benchmark", "Run Snek benchmarks");
    benchmark_step.dependOn(&benchmark_run.step);
}
