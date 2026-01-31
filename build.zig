const std = @import("std");

pub fn build(b: *std.Build) !void {
    //const target = std.Build.standardTargetOptions(b, .{ .default_target = .{ .os_tag = .windows, .ofmt = .coff } });
    const target = std.Build.standardTargetOptions(b, .{});
    const optimize = b.standardOptimizeOption(.{});

    // if (optimize == .ReleaseFast) @compileError("ReleaseFast does not work with ");

    const exe = b.addExecutable(.{
        .name = "rocket-slime-sprite-viewer",
        .linkage = .static,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const sdl3 = b.dependency("sdl3", .{
        .target = target,
        .optimize = optimize,
        .ext_image = true,
        .ext_ttf = true,
    });
    exe.root_module.addImport("sdl3", sdl3.module("sdl3"));

    b.installArtifact(exe);
}
