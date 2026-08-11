const std = @import("std");

pub const Color = packed struct(u16) {
    r: u5,
    g: u5,
    b: u5,
    unused: bool,
};

pub const Palette16 = [16]Color;
pub const Palette256 = [16]Palette16; // 16 palette mode

pub const Tile = extern struct {
    // zig doesn't have packed arrays so this is kinda jank
    data: [8][4]u8,

    pub fn read(self: @This(), x: u5, y: u5) u4 {
        const x_bit = x * 4;

        const row = self.data[y];
        return std.mem.readPackedInt(u4, &row, x_bit, .little);
    }
};

pub const MapEntry = packed struct(u16) {
    tile_number: u10, // Bits 0-9: Tile Number (0-1023)
    h_flip: bool, // Bit 10: Horizontal Flip (0=Normal, 1=Mirrored)
    v_flip: bool, // Bit 11: Vertical Flip (0=Normal, 1=Mirrored)
    palette_number: u4 = 0, // Bits 12-15: only used in 16 palette mode
};

// https://problemkaputt.de/gbatek.htm#lcdobjoamattributes

// this will be merged into a single type once zig supports it
pub const OAMAttr = extern struct {
    attr12: OAMAttr12 align(1),
    attr3: OAMAttr3 align(1),
};

pub const OAMAttr12 = packed struct(u32) {
    y: i8,
    rotScale: bool,
    disabled: bool, // rotation scaling mode is unused in rocket slime I think
    mode: enum(u2) {
        Normal,
        SemiTransparent,
        OBJWindow,
        Prohibited,
    },
    mosaic: bool,
    pal_256_color_mode: bool, // rocket slime only uses 16 palette/16 color mode so this is unused
    shape: enum(u2) {
        Square,
        Horizontal,
        Vertical,
        Prohibited,
    },
    x: i9,
    unused: u3,
    horizontal_flip: bool,
    vertical_flip: bool,
    size: u2, // depends on object shape, 8->16->32->64

    pub fn getTileWidth(self: @This()) usize {
        return @divExact(self.getPixelWidth(), 8);
    }

    pub fn getTileHeight(self: @This()) usize {
        return @divExact(self.getPixelHeight(), 8);
    }

    pub fn getPixelWidth(self: @This()) usize {
        return @as(usize, 8) << switch (self.shape) {
            .Square => self.size,
            .Horizontal => self.size + @intFromBool(self.size < 2),
            .Vertical => self.size - @intFromBool(self.size > 0),
            else => 0,
        };
    }

    pub fn getPixelHeight(self: @This()) usize {
        return @as(usize, 8) << switch (self.shape) {
            .Square => self.size,
            .Horizontal => self.size - @intFromBool(self.size > 0),
            .Vertical => self.size + @intFromBool(self.size < 2),
            else => 0,
        };
    }

    pub fn getTileCount(self: @This()) usize {
        return self.getTileWidth() * self.getTileHeight();
    }
};

pub const OAMAttr3 = packed struct(u16) {
    tile_num: u10,
    priority: u2,
    palette_num: u4,
};

pub const Screen = enum(u1) {
    top,
    bottom,
};
