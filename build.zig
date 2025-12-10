const std = @import("std");
const builtin = @import("builtin");

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
        // FIXME: I'm just using two possible variatons (cpu and os) but there are more
        // This also won't work if you manually specify the exact same target triple as Zig's default
        const is_cross_compiling = target.result.cpu.arch != builtin.target.cpu.arch or target.result.os.tag != builtin.target.os.tag;
        if (is_cross_compiling) {
            // Zig does not automatically include system library paths when cross-compiling
            var code: u8 = 0;
            const sdk_out = std.Build.runAllowFail(b, &.{ "xcrun", "--show-sdk-path" }, &code, .Inherit) catch null;
            if (sdk_out) |s| {
                const sdk = std.mem.trim(u8, s, " \n\r\t");
                exe.root_module.addSystemFrameworkPath(.{ .cwd_relative = std.Build.fmt(b, "{s}/System/Library/Frameworks", .{sdk}) });
                exe.root_module.addLibraryPath(.{ .cwd_relative = std.Build.fmt(b, "{s}/usr/lib", .{sdk}) });
            }
        }
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

    const macos_step = b.step("macOS", "Build and copy executable into snek.app bundle");
    const ensure_dir = b.addSystemCommand(&.{ "mkdir", "-p", "snek.app/Contents/MacOS" });
    macos_step.dependOn(&ensure_dir.step);
    macos_step.dependOn(b.getInstallStep());
    const installed_bin = b.getInstallPath(.bin, exe.out_filename);
    const copy_cmd = b.addSystemCommand(&.{ "cp", "-f", installed_bin, "snek.app/Contents/MacOS/snek" });
    macos_step.dependOn(&copy_cmd.step);
}
