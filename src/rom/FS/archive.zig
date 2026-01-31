const std = @import("std");
const FS = @import("FS.zig");
const file = @import("file.zig");

pub const NDSHeader = extern struct {
    // 0x000 - 0x00B: Game Title (12 bytes)
    game_title: [12]u8,

    // 0x00C - 0x00F: Game Code (4 bytes)
    game_code: [4]u8,

    // 0x010 - 0x011: Maker Code (2 bytes)
    maker_code: [2]u8,

    // 0x012: Unit Code (1 byte)
    unit_code: u8,

    // 0x013: Encryption Seed Select (1 byte)
    encryption_seed: u8,

    // 0x014: Device Capacity (1 byte)
    device_capacity: u8,

    // 0x015 - 0x01B: Reserved (7 bytes)
    reserved1: [7]u8,

    // 0x01C: ROM Version (1 byte)
    rom_version: u8,

    // 0x01D: Flags (1 byte)
    flags: u8,

    // 0x01E - 0x01F: Reserved (2 bytes)
    reserved2: [2]u8,

    // ARM9 Binary Info
    // 0x020: ARM9 ROM Offset (4 bytes)
    arm9_rom_offset: u32,
    // 0x024: ARM9 Entry Address (4 bytes)
    arm9_entry_address: u32,
    // 0x028: ARM9 RAM Address (4 bytes)
    arm9_ram_address: u32,
    // 0x02C: ARM9 Code Size (4 bytes)
    arm9_code_size: u32,

    // ARM7 Binary Info
    // 0x030: ARM7 ROM Offset (4 bytes)
    arm7_rom_offset: u32,
    // 0x034: ARM7 Entry Address (4 bytes)
    arm7_entry_address: u32,
    // 0x038: ARM7 RAM Address (4 bytes)
    arm7_ram_address: u32,
    // 0x03C: ARM7 Code Size (4 bytes)
    arm7_code_size: u32,

    // File System Info
    // 0x040: File Name Table Offset (4 bytes)
    filename_table_offset: u32,
    // 0x044: File Name Table Size (4 bytes)
    filename_table_size: u32,
    // 0x048: FAT Offset (4 bytes)
    fat_offset: u32,
    // 0x04C: FAT Size (4 bytes)
    fat_size: u32,

    // Overlay Info
    // 0x050: ARM9 Overlay Offset (4 bytes)
    arm9_overlay_offset: u32,
    // 0x054: ARM9 Overlay Size (4 bytes)
    arm9_overlay_size: u32,
    // 0x058: ARM7 Overlay Offset (4 bytes)
    arm7_overlay_offset: u32,
    // 0x05C: ARM7 Overlay Size (4 bytes)
    arm7_overlay_size: u32,

    // 0x060: Normal Command Settings (4 bytes)
    normal_command_settings: u32,
    // 0x064: Key1 Command Settings (4 bytes)
    key1_command_settings: u32,

    // 0x068: Icon/Title Offset (4 bytes)
    icon_title_offset: u32,

    // Security
    // 0x06C: Secure Area CRC16 (2 bytes)
    secure_area_crc: u16,
    // 0x06E: Secure Area Loading Timeout (2 bytes)
    secure_area_timeout: u16,

    // 0x070: ARM9 Auto Load List Hook Address (4 bytes)
    arm9_autoload: u32,
    // 0x074: ARM7 Auto Load List Hook Address (4 bytes)
    arm7_autoload: u32,

    // 0x078: Secure Area Disable (8 bytes)
    secure_area_disable: u64,

    // 0x080: Used ROM Size (4 bytes)
    rom_size: u32,
    // 0x084: Header Size (4 bytes)
    header_size: u32,
    // 0x088: Reserved (4 bytes)
    reserved3: u32,

    // Nintendo Logo (156 bytes)
    // 0x08C - 0x127
    nintendo_logo: [156]u8,

    // 0x128: Nintendo Logo CRC (2 bytes)
    logo_crc: u16,
    // 0x12A: Header CRC (2 bytes)
    header_crc: u16,

    // 0x12C - 0x1FF: Reserved (212 bytes)
    reserved4: [212]u8,

    // Ensure the struct is exactly 512 bytes
    comptime {
        if (@sizeOf(@This()) != 512) {
            @compileError("NDSHeader must be 512 bytes");
        }
    }
};

pub const FSArchive = extern struct {
    name: extern union {
        string: [4]u8,
        pack: u32,
    },
    list: file.FSFileLink,
    base: u32,
    fat: u32,
    fat_size: u32,
    fnt: u32,
    fnt_size: u32,

    pub fn OpenFile(
        self: *FSArchive,
        file_name: []const u8,
    ) file.FSFile {
        var out: file.FSFile = std.mem.zeroes(file.FSFile);
        out.arc = self;
        out.props.pos.pos = self.fnt;
        FS.rom.seekTo(out.arc.fnt) catch |err| {
            std.debug.print("Failed to seek to file name table: {}\n", .{err});
            return out;
        };
        const fntentry = FS.rom.deprecatedReader().readStruct(file.FntDirEntry) catch |err| {
            std.debug.print("Failed to read file name table entry: {}\n", .{err});
            return out;
        };
        out.props.pos.pos = fntentry.entry_start;
        out.props.pos.index = fntentry.entry_file_id;
        out.props.parent = fntentry.parent_id;

        for (0..261) |i| {
            out.OpenNextFile(@truncate(i));
            const target_name: []u8 = std.mem.sliceTo(out.props.name, 0);

            if (std.mem.eql(u8, target_name, file_name)) {
                return out;
            }
            out.close();
        }
        return out;
    }
};
