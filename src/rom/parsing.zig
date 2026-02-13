const std = @import("std");
const FS = @import("FS/FS.zig");
const File = @import("FS/file.zig");
const compression = @import("compression.zig");

const mon = @import("mon/mon.zig");
const ent = @import("ent.zig");
const graphics = @import("graphics.zig");

pub fn filename_from_index(index: u64, allocator: std.mem.Allocator) ![]const u8 {
    try FS.rom.seekTo(0x1307C8 + (index * @sizeOf(u32)));
    const addr = try FS.rom.reader().readInt(u32, .little);
    try FS.rom.seekTo(addr - 0x1ffc000);
    try FS.rom.seekBy(1); // skip the "/", it isn't used in the FS.zig parser
    const file_name: []u8 = try FS.rom.reader().readUntilDelimiterAlloc(allocator, 0, 100);

    return file_name;
}

pub fn read_mon_data(filename: []const u8, area_id: u8, allocator: std.mem.Allocator) void {
    var mon_data = FS.rom_archive.OpenFile(filename);
    _ = mon_data.SeekIndexed(0);

    try FS.rom.seekBy(4);
    const length = try FS.rom.reader().readInt(u16, .little);

    const mon_array = allocator.alloc(mon.FS_entry, length) catch {
        std.log.err("Failed to allocate mon array", .{});
        return;
    };

    for (0..length) |i| {
        const mon_entry = try FS.rom.reader().readStruct(mon.FS_entry);
        if ((mon_entry.area_id) == area_id)
            mon_array[i] = mon_entry;
    }
}

pub fn read_area_ent_file_list(address: ent.ListAddresses, allocator: std.mem.Allocator) ![]u8 {
    try FS.rom.seekTo(@intFromEnum(address));

    const file_list: []u8 = try FS.rom.reader().readUntilDelimiterAlloc(allocator, 0, 50);

    return file_list;
}

pub fn read_ent_data(address: ent.ListAddresses, allocator: std.mem.Allocator) ![]ent.FS_entry {
    const file_list = try read_area_ent_file_list(address, allocator);
    const entry_list = try allocator.alloc(ent.FS_entry, file_list.len);
    for (file_list, 0..) |id, i| {
        const file_name = try filename_from_index(id, allocator);
        var ent_data = FS.rom_archive.OpenFile(file_name);
        ent_data.SeekTo();

        entry_list[i] = ent.FS_entry{
            .file_name = file_name,
            .file_data_addr = try FS.rom.getPos(),
            .file_size = ent_data.length(),
        };
    }
    return entry_list;
}

//pub const OAMArray = struct {
//    attributes: []graphics.OAMData,
//};

pub const OAMFileData = struct {
    frames: []graphics.Frame,

    pub fn init_from_rom(allocator: std.mem.Allocator, file: *File.FSFile, fid: u16) !*OAMFileData {
        _ = file.SeekIndexed(fid);
        const out = try allocator.create(OAMFileData);
        try FS.rom.seekBy(2);
        var frame_count: u16 = 0;
        _ = try FS.rom.read(@ptrCast(&frame_count));
        try FS.rom.seekBy(frame_count * @sizeOf(u16)); // skip offsets
        out.frames = try allocator.alloc(graphics.Frame, frame_count);

        for (0..out.frames.len) |i| {
            var obj_count: u16 = 0;
            _ = try FS.rom.read(@ptrCast(&obj_count));
            out.frames[i].attributes = try allocator.alloc(graphics.OAMData, obj_count);
            if (out.frames[i].attributes.len > 0) // note: causes a crash on windows without this check
                _ = try FS.rom.read(@ptrCast(out.frames[i].attributes));
        }

        //const data: *OAMFileData = (std.mem.bytesAsValue(OAMFileData, bytes[0..size]));
        return out;
    }
};

pub fn load_compressed_ent_data(file: *File.FSFile, file_index: u32, uncompressed: bool, allocator: std.mem.Allocator) []u8 {
    const size = file.SeekIndexed(file_index);
    const data: []u8 = allocator.alloc(u8, size) catch {
        @panic("out of memory");
    };
    _ = FS.rom.read(data) catch {};
    const out_dir = std.fs.cwd().openDir("out", .{}) catch {
        @panic("dump error");
    };
    const file_name = std.fmt.allocPrint(allocator, "title_{}.bin", .{file_index}) catch {
        @panic("dump error");
    };
    const file_out = out_dir.createFile(file_name, .{ .read = true }) catch {
        @panic("dump error");
    };
    defer file_out.close();
    _ = file_out.writeAll(data) catch {
        @panic("dump error");
    };
    _ = uncompressed;
    return data;
}

pub fn read_ent_gx_data(file: *File.FSFile, res_entry: *ent.ent_res_entry, screen: graphics.Screen, allocator: std.mem.Allocator, palette: *graphics.Palette256) graphics.Sprite {
    const oam: *OAMFileData = OAMFileData.init_from_rom(allocator, file, res_entry.oam_file_id) catch {
        @panic("error");
    };

    const tilesRaw: []u8 = file.readIndexedRaw(allocator, res_entry.tiles_file_id) catch {
        @panic("error");
    };

    const tiles: []graphics.Tile = @ptrCast(tilesRaw);

    _ = screen;
    return .{
        .oamData = oam,
        .tiles = tiles,
        .palette = palette,
    };
}
