const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "rocket-slime-sprite-viewer",
        .linkage = if (builtin.os.tag == .linux) .dynamic else .static, // windows has trouble with dynamic builds
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
