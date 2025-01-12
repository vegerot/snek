const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const exe = b.addExecutable(.{
        .name = "snek",
        .root_source_file = b.path("snek.zig"),
        .target = target,
        .optimize = optimize,
    });
    const check_step = b.step("check", "");
    check_step.dependOn(&exe.step);

    exe.linkLibC();
    exe.linkSystemLibrary("m");

    if (target.result.isDarwin()) {
        exe.linkFramework("IOKit");
        exe.linkFramework("Cocoa");
    } else if (target.result.os.tag == .windows) {
        exe.linkSystemLibrary("opengl32");
        exe.linkSystemLibrary("gdi32");
        exe.linkSystemLibrary("winmm");
    }

    exe.addIncludePath(b.path("../../raysan5/raylib/src"));
    exe.addLibraryPath(b.path("../../raysan5/raylib/src"));
    exe.linkSystemLibrary("raylib");

    b.installArtifact(exe);

    const game_exe = b.addRunArtifact(exe);
    const play_step = b.step("play", "");
    play_step.dependOn(&game_exe.step);
}
