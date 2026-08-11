const std = @import("std");
const graphics = @import("graphics.zig");

const RGBA = struct { r: u8, g: u8, b: u8, a: u8 };
const Texture = struct {
    data: []RGBA,
    width: usize,
    height: usize,
};

fn write_pixel(texture: Texture, x: usize, y: usize, color: graphics.nds_types.Color) void {
    texture.data[x + y * texture.width] = .{
        .r = @as(u8, color.r) << 3,
        .g = @as(u8, color.g) << 3,
        .b = @as(u8, color.b) << 3,
        .a = 255, // alpha is always 255
        // TODO: check that alpha isn't actually needed
    };
}

fn create_texture(width: usize, height: usize, allocator: std.mem.Allocator) error{OutOfMemory}!Texture {
    const out: []align(1) RGBA = try allocator.alloc(RGBA, width * height);
    for (out) |*pixel| pixel.a = 0;
    return .{
        .data = out,
        .width = width,
        .height = height,
    };
}

pub const renderer = graphics.BuildRenderer(Texture, &create_texture, &write_pixel);
