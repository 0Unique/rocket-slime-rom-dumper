const std = @import("std");

const file = @import("file.zig");
const archive = @import("archive.zig");
pub var rom_archive: archive.FSArchive = std.mem.zeroes(archive.FSArchive);
pub var rom: *std.fs.File = undefined;

pub fn init(rom_path: []const u8, allocator: std.mem.Allocator) bool {
    rom = allocator.create(std.fs.File) catch |err| {
        std.log.err("Failed to create rom file: {}\n", .{err});
        return false;
    };

    rom.* = std.fs.openFileAbsolute(rom_path, .{ .mode = .read_only }) catch |err| {
        std.log.err("Failed to open rom: {}\n", .{err});
        return false;
    };

    const header: archive.NDSHeader = rom.deprecatedReader().readStruct(archive.NDSHeader) catch |err| {
        std.log.err("Failed to read header: {}\n", .{err});
        return false;
    };

    std.debug.print("Game Title: {s}\n", .{header.game_title});

    // init "rom" archive
    rom_archive.base = 0;
    rom_archive.fat_size = header.fat_size;
    rom_archive.fat = header.fat_offset;
    rom_archive.fnt_size = header.filename_table_size;
    rom_archive.fnt = header.filename_table_offset;
    return true;
}

pub fn deinit() void {
    rom.close();
}
