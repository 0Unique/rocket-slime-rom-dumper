const std = @import("std");
pub const nds_types = @import("nds_types.zig");
pub const rs_types = @import("rs_types.zig");

pub fn BuildRenderer(
    texture_type: type,
    create_texture: (*const fn (width: usize, height: usize, allocator: std.mem.Allocator) error{OutOfMemory}!texture_type),
    write_pixel: (*const fn (texture: texture_type, x: usize, y: usize, color: nds_types.Color) void),
) type {
    return struct {
        pub const texture_priority_map = []u2;

        pub const nds_texture = struct {
            texture: texture_type,
            width: usize,
            height: usize,

            pub fn create(width: usize, height: usize, allocator: std.mem.Allocator) error{OutOfMemory}!@This() {
                return .{
                    .texture = try create_texture(width, height, allocator),
                    .width = width,
                    .height = height,
                };
            }
        };

        pub fn renderTile(texture: nds_texture, x: usize, y: usize, tile: nds_types.Tile, palette: nds_types.Palette16, h_flip: bool, v_flip: bool) void {
            for (0..8) |py| {
                const src_y = if (v_flip) 7 - py else py;
                for (0..8) |px| {
                    const src_x = if (h_flip) 7 - px else px;
                    const pal_ind = tile.read(@intCast(px), @intCast(py));

                    if (pal_ind != 0)
                        write_pixel(texture.texture, x + src_x, y + src_y, palette[pal_ind]);
                }
            }
        }

        pub fn renderMap(texture: nds_texture, x: usize, y: usize, map: []align(1) const nds_types.MapEntry, tileset: []align(1) const nds_types.Tile, palettes: []align(1) const nds_types.Palette16) void {
            const tw = texture.width / 8;
            for (map, 0..) |entry, i| {
                const tile = tileset[entry.tile_number];
                const px = i % tw;
                const py = @divTrunc(i, tw);
                renderTile(texture, x + px * 8, y + py * 8, tile, palettes[entry.palette_number], entry.h_flip, entry.v_flip);
            }
        }

        pub fn renderMaps(allocator: std.mem.Allocator, width: usize, height: usize, maps: [][]align(1) const nds_types.MapEntry, tileset: []align(1) const nds_types.Tile, palettes: []align(1) const nds_types.Palette16) !nds_texture {
            const out = try create_texture(width * 8, height * 8, allocator);
            var bottom = false;
            for (maps) |map| {
                renderMap(out, 0, if (bottom) height * 8 / 2 else 0, width, map, tileset, palettes);
                bottom = !bottom;
            }

            return out;
        }

        pub fn renderOAM(texture: nds_texture, x: usize, y: usize, attr: nds_types.OAMAttr, tiles: []align(1) const nds_types.Tile, palettes: []align(1) const nds_types.Palette16) void {
            const width = attr.attr12.getTileWidth();
            const height = attr.attr12.getTileHeight();

            for (0..width) |tx| {
                for (0..height) |ty| {
                    const ax = if (attr.attr12.horizontal_flip) width - tx - 1 else tx;
                    const ay = if (attr.attr12.vertical_flip) height - ty - 1 else ty;
                    renderTile(texture, x + ax * 8, y + ay * 8, tiles[attr.attr3.tile_num * 4 + tx + ty * width], palettes[attr.attr3.palette_num], attr.attr12.horizontal_flip, attr.attr12.vertical_flip);
                }
            }
        }

        pub fn renderPackedOAM(sprite: rs_types.packedOAMsprite, allocator: std.mem.Allocator) ![]?nds_texture {
            if (sprite.frames.len == 0)
                return error.NoFrames;
            if (sprite.tiles.len == 0)
                return error.NoTiles;
            if (sprite.palettes.len == 0)
                return error.NoPalettes;

            const out = try allocator.alloc(?nds_texture, sprite.frames.len);

            for (sprite.frames, 0..) |frame, i| {
                const rect = frame.get_rect() catch {
                    out[i] = null;
                    continue;
                };
                out[i] = try nds_texture.create(rect.width, rect.height, allocator);

                // OAM attributes are processed in reverse order
                var attr_iter = std.mem.reverseIterator(frame.OAMattributes.?);
                while (attr_iter.next()) |attr| {
                    renderOAM(out[i].?, @abs(attr.attr12.x - rect.offset_x), @abs(attr.attr12.y - rect.offset_y), attr, sprite.tiles, sprite.palettes);
                }
            }

            return out;
        }
    };
}
