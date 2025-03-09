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

    // Define a command to run another build.zig file
    const raylib_build_command = b.addSystemCommand(&.{ "zig", "build" });
    raylib_build_command.setCwd(b.path("raylib"));
    raylib_build_command.addCheck(.{ .expect_term = .{ .Exited = 0 } });
    exe.step.dependOn(&raylib_build_command.step);

    const freetype_build_command = b.addSystemCommand(&.{ "zig", "build" });
    freetype_build_command.setCwd(b.path("freetype"));
    freetype_build_command.addCheck(.{ .expect_term = .{ .Exited = 0 } });
    exe.step.dependOn(&freetype_build_command.step);

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

    exe.addIncludePath(b.path("./raylib/src"));
    exe.addLibraryPath(b.path("./raylib/zig-out/lib/"));
    exe.linkSystemLibrary("raylib");

    exe.addIncludePath(b.path("./freetype/zig-out/include"));
    exe.addLibraryPath(b.path("./freetype/zig-out/lib/"));
    exe.linkSystemLibrary("freetype");

    exe.addIncludePath(b.path("./"));

    b.installArtifact(exe);

    const game_exe = b.addRunArtifact(exe);
    const play_step = b.step("play", "");
    play_step.dependOn(&game_exe.step);
}
