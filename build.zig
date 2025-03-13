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

        exe.addIncludePath(std.Build.LazyPath{ .cwd_relative = "/opt/homebrew/include/librsvg-2.0/librsvg" });
        exe.addLibraryPath(std.Build.LazyPath{ .cwd_relative = "/opt/homebrew/lib" });
        exe.linkSystemLibrary("rsvg-2");
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

    const freetype = b.dependency("freetype", .{
        .target = target,
        .optimize = optimize,
    });
    exe.linkLibrary(freetype.artifact("freetype"));

    exe.addIncludePath(b.path("./"));

    b.installArtifact(exe);

    const game_exe = b.addRunArtifact(exe);
    const play_step = b.step("play", "");
    play_step.dependOn(&game_exe.step);
}
