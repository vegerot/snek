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

    linkStuff(b, target, optimize, exe);

    // copy these absolute path font files to the build directory
    const font_path = switch (target.result.os.tag) {
        .windows => "C:\\Windows\\Fonts\\SEGUIEMJ.TTF",
        .macos => "/System/Library/Fonts/Apple Color Emoji.ttc",
        .linux => "./seguiemj.ttf",
        else => unreachable(),
    };

    const cp_step = b.addSystemCommand(&.{"cp"});
    cp_step.addFileArg(std.Build.LazyPath{ .cwd_relative = font_path });
    const fontFile = cp_step.addOutputFileArg("./.font.ttfc");
    std.debug.print("font file: {}\n", .{fontFile});
    exe.root_module.addAnonymousImport("font", .{
        .root_source_file = fontFile,
    });

    b.installArtifact(exe);

    const game_exe = b.addRunArtifact(exe);
    const play_step = b.step("play", "");
    play_step.dependOn(&game_exe.step);
}

fn linkStuff(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, exe: *std.Build.Step.Compile) void {
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
    if (target.result.isDarwin()) {
        // work around fucked
        // make sure to run brew install freetype
        exe.addLibraryPath(std.Build.LazyPath{ .cwd_relative = "/opt/homebrew/lib" });
        exe.addIncludePath(b.path("./freetype/zig-out/include"));
        exe.addLibraryPath(b.path("./freetype/zig-out/lib/"));
        exe.linkSystemLibrary("freetype");
    } else {
        exe.linkLibrary(freetype.artifact("freetype"));
    }

    exe.addIncludePath(b.path("./"));
}
