const std = @import("std");
const nds_types = @import("nds_types.zig");

pub const PackedFile = [][]align(1) const u8;

pub const File = struct {
    data: []align(1) const u8,

    fn packedFileCount(self: @This()) u32 {
        return std.mem.readInt(u32, self.data[0..@sizeOf(u32)], .little);
    }

    fn packedFileOffset(self: @This(), index: usize) u32 {
        return std.mem.readInt(u32, self.data[4 + index * 8 ..][0..@sizeOf(u32)], .little);
    }

    fn packedFileSize(self: @This(), index: usize) u32 {
        return std.mem.readInt(u32, self.data[8 + index * 8 ..][0..@sizeOf(u32)], .little);
    }

    fn packedFileContent(self: @This(), index: usize) []align(1) const u8 {
        const count = self.packedFileCount();
        const offset = self.packedFileOffset(index);
        const size = self.packedFileSize(index);
        return self.data[offset + count * 8 + 4 ..][0..size];
    }

    pub fn unpack(self: @This(), allocator: std.mem.Allocator) !PackedFile {
        const count = self.packedFileCount();
        const out = try allocator.alloc([]const u8, count);
        for (0..count) |i| {
            out[i] = self.packedFileContent(i);
        }
        return out;
    }
};
pub const FileMap = std.StringHashMap(File);

pub const rom = struct {
    data: []align(1) const u8,
    header: *align(1) nds_types.NDSHeader,
    files: FileMap,

    pub fn open(io: std.Io, rom_path: []const u8, allocator: std.mem.Allocator) !@This() {
        const rom_file: std.Io.File = try std.Io.Dir.openFileAbsolute(io, rom_path, .{ .mode = .read_only });
        const size = (try rom_file.stat(io)).size;
        var data = try allocator.alloc(u8, size);
        _ = try rom_file.readPositionalAll(io, data, 0);
        rom_file.close(io);

        const header: *align(1) nds_types.NDSHeader = @ptrCast(&data[0]);

        const fat: []align(1) const nds_types.FatFileEntry = @ptrCast(data[header.fat_offset..][0..header.fat_size]);
        const fnt = data[header.filename_table_offset..][0..header.filename_table_size];

        var out: @This() = .{
            .data = data,
            .header = header,
            .files = undefined,
        };

        out.files = try out.build_file_table(fnt, fat, allocator);
        return out;
    }

    pub fn build_file_table(self: @This(), fnt: []const u8, fat: []align(1) const nds_types.FatFileEntry, allocator: std.mem.Allocator) !FileMap {
        var out: FileMap = .init(allocator);

        const dirEntry: *align(1) const nds_types.FntDirEntry = @ptrCast(&fnt[0]);
        var pos = dirEntry.entry_start;
        var name_len = fnt[pos];
        for (fat) |fat_entry| {
            const name = fnt[pos + 1 ..][0..name_len];
            const file_content: []align(1) const u8 = self.data[fat_entry.top..fat_entry.bottom];
            try out.putNoClobber(name, .{ .data = file_content });
            pos += name_len + 1;
            name_len = fnt[pos];
        }

        return out;
    }
};
