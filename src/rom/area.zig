const std = @import("std");
const ct = @import("comptime_util.zig");
const FS = @import("FS/FS.zig");
const compression = @import("compression.zig");
const graphics = @import("graphics/graphics.zig");

const area_file_ids = extern struct {
    width: u16,
    height: u16,
    BGs_used: packed struct(u8) {
        unknown1: bool,
        bg1_map: bool,
        bg3_map: bool,
        unknown4: bool,
        main_bg_tiles: bool,
        main_bg_tiles2: bool,
        shared_bg_tiles: bool,
        unknown8: bool,
    },
    unknown: u8, // related to entities
    tiles_fid: u16, // bottom screen lz16 compressed, not compressed in tank battles
    palette_fid: u16,
    extra_maps_fid: u16,
    maps_fid: u16,

    const tank_battle: struct { address: u32, len: usize } = .{ .address = ct.address(0x0212a9f0), .len = 210 };
    const non_tank_battle: struct { address: u32, len: usize } = .{ .address = ct.address(0x021281f4), .len = 220 };

    // TODO: lots of edge cases for how these are loaded
    fn load_non_tank(rom: FS.rom) []align(1) const @This() {
        return @ptrCast(rom.data[non_tank_battle.address..][0 .. non_tank_battle.len * @sizeOf(@This())]);
    }

    // TODO: tank battles
    // loading tank battles in the same way as non tank battles doesn't work
    // tank battle tilemaps aren't compressed
};

// function in the rom is at 0x020c9af8
// TODO: check accuracy of this compared to what the rom outputs
// in the forewood tutorial (areas 0x40, 0x41, and 0x42) it only loads 1 palette instead of all 5 - thats what param 2 in the original function is
pub fn has_five_palettes(area_id: usize) bool {
    return switch (area_id) {
        0x02, 0x03, 0x06, 0x07, 0x08, 0x0b, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1f, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x29, 0x2a, 0x2b, 0x2c, 0x2d, 0x2e, 0x2f, 0x31, 0x32, 0x33, 0x39, 0x3a, 0x3b, 0x47, 0x4c, 0x79, 0x7a, 0x7b, 0x7c, 0x7d, 0x7e, 0x7f, 0x83, 0x9a, 0xa3, 0xa4, 0xa5, 0xa6, 0xaf, 0xb0, 0xb1, 0xb5, 0xd5, 0xd6, 0xd7, 0xd8, 0xda => false,
        else => true,
    };
}

pub const area_files = struct {
    width: u16,
    height: u16,

    tiles: []align(1) const graphics.nds_types.Tile,
    shared_tiles: ?[]align(1) const graphics.nds_types.Tile,
    palettes: [][]align(1) const graphics.nds_types.Palette16,
    extra_maps: []align(1) const graphics.nds_types.MapEntry,
    maps: [][]align(1) const graphics.nds_types.MapEntry,

    // might be used to display debug info in the future
    rom_entry: *align(1) const area_file_ids,

    pub fn load_non_tank(allocator: std.mem.Allocator, rom: FS.rom) ![]@This() {
        var out: []@This() = std.mem.zeroes([]@This());

        const entry = area_file_ids.load_non_tank(rom);
        const filename = "stage_bg.bin"; // "bg_data.bin" for tank battles
        const file = rom.files.get(filename);
        if (file) |f| {
            const files = try f.unpack(allocator);
            out = try allocator.alloc(@This(), entry.len);
            for (entry, 0..) |fids, area_id| {
                const size = fids.width * fids.height;
                const map_count = files[fids.maps_fid].len / size;
                const maps = try allocator.alloc([]align(1) const graphics.nds_types.MapEntry, map_count);
                for (maps, 0..) |*map, i| map.* = @ptrCast(files[fids.maps_fid][i * size ..][0..size]);

                const palette_count: usize = if (has_five_palettes(area_id)) 5 else 1;

                var palettes: [][]align(1) const graphics.nds_types.Palette16 = try allocator.alloc([]align(1) const graphics.nds_types.Palette16, palette_count);
                for (palettes, 0..) |_, i| {
                    palettes[i] = @ptrCast((files[fids.palette_fid + i]));
                }

                out[area_id] = .{
                    .width = fids.width,
                    .height = fids.height,

                    .tiles = @ptrCast(try compression.decompress16(files[fids.tiles_fid], allocator)),
                    .shared_tiles = if (fids.BGs_used.shared_bg_tiles) @ptrCast(try compression.decompress16(files[fids.tiles_fid + 1], allocator)) else null,
                    .palettes = palettes,
                    .extra_maps = @ptrCast(files[fids.extra_maps_fid]),
                    .maps = maps,

                    .rom_entry = &fids,
                };
            }
        } else {
            return error.FileNotFound;
        }

        return out;
    }
};
