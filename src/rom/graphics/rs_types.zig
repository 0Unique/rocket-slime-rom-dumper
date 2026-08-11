const std = @import("std");
const nds_types = @import("nds_types.zig");

pub const packedOAMsprite = struct {
    frames: []packedOAMframe,
    palettes: []align(1) const nds_types.Palette16,
    tiles: []align(1) const nds_types.Tile,

    pub fn read(allocator: std.mem.Allocator, data: []const u8, tiles: []align(1) const nds_types.Tile, palettes: []align(1) const nds_types.Palette16) !@This() {
        var out = std.mem.zeroes(@This());
        out.tiles = tiles;
        out.palettes = palettes;

        const frame_count: u16 = std.mem.readInt(u16, data[2..4], .little);

        var pos: usize = frame_count * @sizeOf(u16) + 4; // skip offsets
        out.frames = try allocator.alloc(packedOAMframe, @as(usize, (frame_count)));

        for (0..out.frames.len) |i| {
            const obj_count: u16 = std.mem.readInt(u16, data[pos..][0..2], .little);
            pos += 2;
            if (obj_count != 0) {
                out.frames[i] = .{ .OAMattributes = @ptrCast(data[pos..][0 .. obj_count * 6]) };
                pos += obj_count * 6;
            } else out.frames[i].OAMattributes = null;
        }

        return out;
    }
};

pub const packedOAMframe = struct {
    OAMattributes: ?[]align(1) const nds_types.OAMAttr align(1),

    const Rect = struct {
        width: usize,
        height: usize,
        offset_x: i9,
        offset_y: i10,
    };

    pub fn get_rect(self: @This()) error{NoOamObjects}!Rect {
        if (self.OAMattributes == null or self.OAMattributes.?.len == 0)
            return error.NoOamObjects;

        var width: usize = 0;
        var height: usize = 0;
        var minOffsetX: i9 = 0;
        var minOffsetY: i10 = 0;

        for (self.OAMattributes.?) |attr| {
            if (attr.attr12.x < minOffsetX) minOffsetX = attr.attr12.x;
            if (attr.attr12.y < minOffsetY) minOffsetY = attr.attr12.y;
        }

        for (self.OAMattributes.?) |attr| {
            const w = attr.attr12.getPixelWidth();
            const h = attr.attr12.getPixelHeight();
            const adjX: usize = @abs(@as(isize, @intCast(attr.attr12.x)) - @as(isize, @intCast(minOffsetX)));
            const adjY: usize = @abs(@as(isize, @intCast(attr.attr12.y)) - @as(isize, @intCast(minOffsetY)));
            const xw = adjX + w;
            const yh = adjY + h;

            if (xw > width) width = xw;
            if (yh > height) height = yh;
        }

        return .{
            .width = width,
            .height = height,
            .offset_x = minOffsetX,
            .offset_y = minOffsetY,
        };
    }
};
