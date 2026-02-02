const std = @import("std");
const sdl3 = @import("sdl3");
const FS = @import("FS/FS.zig");
const file = @import("FS/file.zig");
const parsing = @import("parsing.zig");

pub const Color = packed struct(u16) {
    r: u5,
    g: u5,
    b: u5,
    padding: u1,

    fn toSDL(self: *Color) sdl3.pixels.Color {
        return .{
            .r = @as(u8, self.r) << 3,
            .g = @as(u8, self.g) << 3,
            .b = @as(u8, self.b) << 3,
            .a = 255,
        };
    }
};

pub const Palette16 = [16]Color;
pub const Palette256 = [16]Palette16; // 16 palette mode

pub const Tile = extern struct {
    dots: [8][4]TilePixel, // 8x8 tile, each byte selects a palette entry
};
pub const TilePixel = packed struct(u8) {
    left: u4,
    right: u4,
};

const MapEntry = packed struct(u16) {
    tile_number: u10, // Bits 0-9: Tile Number (0-1023)
    h_flip: bool, // Bit 10: Horizontal Flip (0=Normal, 1=Mirrored)
    v_flip: bool, // Bit 11: Vertical Flip (0=Normal, 1=Mirrored)
    palette_number: u4 = 0, // Bits 12-15: only used in 16 palette mode
};

const RotationScalingMapEntry = packed struct(u8) {
    tile_number: u8, // Tile Number (0-255)
};

pub const area_data = packed struct {
    width: u16,
    height: u16,
    unknown: u16, // not sure what this is used for
    file_index1: u16, // still need to figure out what these files actually are
    file_index2: u16,
    loaded_index1: u16, // file data array index if they are loaded
    loaded_index2: u16,
};

pub fn readAreaData(area_id: usize) !area_data {
    const base_addr = 0x12C1F4; // 0x12E9F0 for tank battles
    try FS.rom.seekTo(base_addr + area_id * @sizeOf(area_data));
    return try FS.rom.reader().readStruct(area_data);
}

pub fn debugPrintPalette(pal: *Palette256) void {
    const palette: *[256]Color = @ptrCast(pal);
    for (palette, 0..) |color, i| {
        if (i % 16 == 0) {
            std.debug.print("\n", .{});
        }
        const red = @as(u8, color.r) << 3;
        const green = @as(u8, color.g) << 3;
        const blue = @as(u8, color.b) << 3;
        std.debug.print(
            "\x1b[48;2;{d};{d};{d}m  \x1b[0m",
            .{
                red,
                green,
                blue,
            },
        );
    }
    std.debug.print("\n", .{});
}

pub fn load_tile_map(palette: *Palette256, rom_file: *file.FSFile, tiles_file_index: i64, map_file_index: i64, allocator: std.mem.Allocator) !sdl3.surface.Surface {
    const tiles_size = rom_file.SeekIndexed(tiles_file_index);
    const tile_count = tiles_size / @sizeOf(Tile);
    const tiles: []Tile = try allocator.alloc(Tile, tile_count);
    _ = try FS.rom.read(@ptrCast(tiles));

    const map_size = rom_file.SeekIndexed(map_file_index);
    const entry_count = map_size / @sizeOf(MapEntry);
    const map_count = entry_count / 0x400;
    const entries: []MapEntry = try allocator.alloc(MapEntry, entry_count);
    _ = try FS.rom.read(@ptrCast(entries));

    const surface = try sdl3.surface.Surface.init(entry_count * 8 * 32, map_count * 8 * 32, .packed_rgba_5_5_5_1);

    for (entries, 0..) |entry, i| {
        const entry_y: usize = @intCast(i / 32);
        const entry_x: usize = @intCast(i % 32);
        const tile = tiles[entry.tile_number];

        for (tile.dots, 0..) |pixel_row, y| {
            for (pixel_row, 0..) |palette_index, x| {
                var acX = x * 2;
                var acY = y;
                if (entry.h_flip) acX = 6 - acX;
                if (entry.v_flip) acY = 7 - acY;
                var colorLeft = palette[entry.palette_number][palette_index.left].toSDL();
                if (palette_index.left == 0) colorLeft.a = 0;
                try surface.writePixel(acX + entry_x * 8, acY + entry_y * 8, colorLeft);

                var colorRight = palette[entry.palette_number][palette_index.right].toSDL();
                if (palette_index.right == 0) colorRight.a = 0;
                try surface.writePixel(acX + 1 + entry_x * 8, acY + entry_y * 8, colorRight);
            }
        }
    }
    return surface;
}

pub fn load_tile_map_tex(palette: *Palette256, rom_file: *file.FSFile, tiles_file_index: i64, map_file_index: i64, allocator: std.mem.Allocator, renderer: *sdl3.render.Renderer) !sdl3.render.Texture {
    const tiles_size = rom_file.SeekIndexed(tiles_file_index);
    const tile_count = tiles_size / @sizeOf(Tile);
    const tiles: []Tile = try allocator.alloc(Tile, tile_count);
    _ = try FS.rom.read(@ptrCast(tiles));

    const map_size = rom_file.SeekIndexed(map_file_index);
    const entry_count = map_size / @sizeOf(MapEntry);
    const map_count = entry_count / 0x400;
    const entries: []MapEntry = try allocator.alloc(MapEntry, entry_count);
    _ = try FS.rom.read(@ptrCast(entries));

    const width = 8 * 32;
    const height = map_count * 8 * 32;

    // Create a temporary surface to draw on
    const surface = try sdl3.surface.Surface.init(width, height, .packed_rgba_5_5_5_1);

    for (entries, 0..) |entry, i| {
        const entry_y: usize = @intCast(i / 32);
        const entry_x: usize = @intCast(i % 32);
        const tile = tiles[entry.tile_number];

        for (tile.dots, 0..) |pixel_row, y| {
            for (pixel_row, 0..) |palette_index, x| {
                var acX = x * 2;
                var acY = y;
                if (entry.h_flip) acX = 6 - acX;
                if (entry.v_flip) acY = 7 - acY;
                var colorLeft = palette[entry.palette_number][palette_index.left].toSDL();
                if (palette_index.left == 0) colorLeft.a = 0;
                try surface.writePixel(acX + entry_x * 8, acY + entry_y * 8, colorLeft);

                var colorRight = palette[entry.palette_number][palette_index.right].toSDL();
                if (palette_index.right == 0) colorRight.a = 0;
                try surface.writePixel(acX + 1 + entry_x * 8, acY + entry_y * 8, colorRight);
            }
        }
    }

    // Create texture from the surface
    const texture = renderer.createTextureFromSurface(surface) catch {
        std.log.err("sdl3 texture rendering error: {s}", .{sdl3.errors.get().?});
        @panic("crash");
    };

    // Free the temporary surface
    surface.deinit();

    return texture;
}

const OBJ_Mode = enum(u2) {
    Normal,
    SemiTransparent,
    OBJWindow,
    Prohibited,
};

const OBJ_Shape = enum(u2) {
    Square,
    Horizontal,
    Vertical,
    Prohibited,
};

// https://problemkaputt.de/gbatek.htm#lcdobjoamattributes
pub const OAMAttr12 = packed struct(u32) {
    y: i8,
    rotScale: bool,
    disabled: bool, // rotation scaling mode is unused in rocket slime I think
    mode: OBJ_Mode, // u2: (0=Normal, 1=Semi-Transparent, 2=OBJ Window, 3=Prohibited)
    mosaic: bool,
    pal_256_color_mode: bool, // rocket slime only uses 16 palette/16 color mode so this is unused
    shape: OBJ_Shape,
    x: i9,
    unused: u3,
    horizontal_flip: bool,
    vertical_flip: bool,
    size: u2, // depends on object shape, 8->16->32->64

    pub fn getTileWidth(self: *align(2) const OAMAttr12) usize {
        return @divExact(self.getPixelWidth(), 8);
    }

    pub fn getTileHeight(self: *align(2) const OAMAttr12) usize {
        return @divExact(self.getPixelHeight(), 8);
    }

    pub fn getPixelWidth(self: *align(2) const OAMAttr12) usize {
        return @as(usize, 8) << switch (self.shape) {
            .Square => self.size,
            .Horizontal => self.size + @intFromBool(self.size < 2),
            .Vertical => self.size - @intFromBool(self.size > 0),
            else => 0,
        };
    }

    pub fn getPixelHeight(self: *align(2) const OAMAttr12) usize {
        return @as(usize, 8) << switch (self.shape) {
            .Square => self.size,
            .Horizontal => self.size - @intFromBool(self.size > 0),
            .Vertical => self.size + @intFromBool(self.size < 2),
            else => 0,
        };
    }

    pub fn getTileCount(self: *align(2) const OAMAttr12) usize {
        return self.getTileWidth() * self.getTileHeight() + 1;
    }
};

pub const OAMAttr3 = packed struct(u16) {
    tile_num: u10,
    priority: u2,
    palette_num: u4,
};

// has to be done a little weirdly cause of alignment issues
pub const OAMData = extern struct {
    attr12: OAMAttr12 align(2),
    attr3: OAMAttr3 align(2),

    comptime {
        if (@sizeOf(@This()) != 6) {
            const msg = std.fmt.comptimePrint("OAMData must be 6 bytes, is {}", .{@sizeOf(@This())});
            @compileError(msg);
        }
    }
};

pub const Frame = struct {
    attributes: []OAMData,
};

pub const Sprite = struct {
    oamData: *parsing.OAMFileData,
    tiles: []Tile,
    palette: *Palette256,

    // only used for showing in ui
    oam_id: u16 = 0,
    tiles_id: u16 = 0,

    pub fn createSurface(self: *Sprite, frame_num: usize) !sdl3.surface.Surface {
        if (self.oamData.frames[frame_num].attributes.len == 0)
            return error.NoOamAttributes;
        if (self.tiles.len == 0)
            return error.NoTiles;
        var surf_width: u64 = 0;
        var surf_height: u64 = 0;
        var minOffsetX: i9 = 0;
        var minOffsetY: i10 = 0;

        // get min offset
        for (self.oamData.frames[frame_num].attributes) |attr| {
            if (attr.attr12.x < minOffsetX) minOffsetX = attr.attr12.x;
            if (attr.attr12.y < minOffsetY) minOffsetY = attr.attr12.y;
        }

        for (self.oamData.frames[frame_num].attributes) |attr| {
            const w = attr.attr12.getPixelWidth();
            const h = attr.attr12.getPixelHeight();
            const adjX: usize = @abs(@as(isize, @intCast(attr.attr12.x)) - @as(isize, @intCast(minOffsetX)));
            const adjY: usize = @abs(@as(isize, @intCast(attr.attr12.y)) - @as(isize, @intCast(minOffsetY)));
            const xw = adjX + w;
            const yh = adjY + h;

            if (xw > surf_width) surf_width = xw;
            if (yh > surf_height) surf_height = yh;
        }

        // the size it creates here is a bit larger then its supposed to be but its fine for now
        const surface = try sdl3.surface.Surface.init(surf_width, surf_height, .packed_rgba_5_5_5_1);

        for (self.oamData.frames[frame_num].attributes) |attr| {
            const width = attr.attr12.getTileWidth();

            var tile_x: u16 = 0;
            var tile_y: u16 = 0;

            for (0..attr.attr12.getTileCount() - 1) |i| {
                const tile = self.tiles[i + attr.attr3.tile_num * 4];

                for (tile.dots, 0..) |pixel_row, y| {
                    for (pixel_row, 0..) |palette_index, x| {
                        var acX = x * 2;
                        var acY = y;
                        if (attr.attr12.horizontal_flip) acX = 6 - acX;
                        if (attr.attr12.vertical_flip) acY = 7 - acY;
                        var colorLeft = self.palette[attr.attr3.palette_num][palette_index.left].toSDL();
                        if (palette_index.left == 0) colorLeft.a = 0;
                        try surface.writePixel(acX + tile_x * 8 + @abs(attr.attr12.x + @as(i9, @intCast(@abs(minOffsetX)))), acY + tile_y * 8 + @abs(attr.attr12.y + @as(i10, @intCast(@abs(minOffsetY)))), colorLeft);

                        var colorRight = self.palette[attr.attr3.palette_num][palette_index.right].toSDL();
                        if (palette_index.right == 0) colorRight.a = 0;
                        try surface.writePixel(acX + 1 + tile_x * 8 + @abs(attr.attr12.x + @as(i9, @intCast(@abs(minOffsetX)))), acY + tile_y * 8 + @abs(attr.attr12.y + @as(i10, @intCast(@abs(minOffsetY)))), colorRight);
                    }
                }

                tile_x += 1;
                if (tile_x == width) {
                    tile_x = 0;
                    tile_y += 1;
                }
            }
        }
        return surface;
    }
};

pub const Screen = enum(u1) {
    top,
    bottom,
};
