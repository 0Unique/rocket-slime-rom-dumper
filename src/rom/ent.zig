const std = @import("std");
const graphics = @import("graphics.zig");
const file = @import("FS/file.zig");
const ct = @import("comptime_util.zig");
const FS = @import("FS/FS.zig");
const parser = @import("parsing.zig");

pub const FS_entry = struct {
    file_name: []const u8,
    file_data_addr: u64,
    file_size: u32,
};

//these are hardcoded in the rom
pub const ListAddresses = enum(u64) {
    forewood = 0x13222C, // add 0x1FFC000 to get the address in ghidra
    tootinschleiman = 0x132240,
    // TODO: add the rest
};

pub const def = extern struct {
    capabilities: u8,
    file_index: u8,
    unknown: u16,
    file_index2: u8,
    unknown2: u8,
    unknown3: u8,
    unknown4: u8,

    // pointers to functions
    func1: u32,
    func2: u32,
    update_func: u32,
    func4: u32,
    func5: u32,

    //rest is unknown
    unknowns: [40]u8,

    comptime {
        if (@sizeOf(@This()) != 0x44) {
            @compileError("ent def must be 0x44 bytes");
        }
    }
};

pub const entity_resources = extern struct {
    unknowns: u8[8],
    palette_maybe_ptr: u32,
    comptime {
        if (@sizeOf(@This()) != 0x4c) {
            @compileError("ent resources must be 0x4c bytes");
        }
    }
};

pub const ent_res_entry = struct {
    x: u16 align(2),
    y: u16 align(2),
    oam_file_id: u16 align(2),
    tiles_file_id: u16 align(2),

    //something to do with animations
    flags: u16 align(2),
    flags2: u16 align(2),
    flags3: u16 align(2),
    flags4: u16 align(2),
    unknown: u16 align(2),
    comptime {
        if (@sizeOf(@This()) != 0x12) {
            const msg = std.fmt.comptimePrint("ent_res_entry must be 0x12 bytes, is {}", .{@sizeOf(@This())});
            @compileError(msg);
        }
    }
};

pub const ent_res_list = struct {
    label: []const u8,
    ent_count: usize,
    address: u64,
    screen: graphics.Screen,
    compressed: bool = false,
    file_name: []const u8,
    palette_fid: u16,

    pub fn load_sprites(self: *const ent_res_list, allocator: *std.mem.Allocator) ![]graphics.Sprite {
        var rom_file: file.FSFile = FS.rom_archive.OpenFile(self.file_name);
        const palette: *graphics.Palette256 = try rom_file.readIndexedStruct(allocator, self.palette_fid, graphics.Palette256);

        const entries = try allocator.alloc(ent_res_entry, self.ent_count);
        try FS.rom.seekTo(self.address);
        _ = try FS.rom.read(@as([]u8, @ptrCast(entries)));

        var sprites = try allocator.alloc(graphics.Sprite, self.ent_count);

        for (entries, 0..) |entry, i| {
            sprites[i] = parser.read_ent_gx_data(&rom_file, @constCast(&entry), self.screen, allocator, palette);
            sprites[i].oam_id = entry.oam_file_id;
            sprites[i].tiles_id = entry.tiles_file_id;
        }

        return sprites;
    }
};

pub const ent_res_entry_lists: [23]ent_res_list = .{
    .{
        .label = "title top screen",
        .ent_count = 6,
        .address = ct.address(0x021337d0),
        .screen = .top,
        .file_name = "optitle_data.bin",
        .palette_fid = 0x8b,
    },
    .{
        .label = "title bottom screen",
        .ent_count = 0x11,
        .address = ct.address(0x0213383c),
        .screen = .bottom,
        .file_name = "optitle_data.bin",
        .palette_fid = 0x11,
    },
    .{
        .label = "data select award?",
        .ent_count = 0x1,
        .address = ct.address(0x02133440),
        .screen = .top,
        .file_name = "dataselect_data.bin",
        .palette_fid = 0x22,
    },
    .{
        .label = "alchemy win data",
        .ent_count = 7,
        .address = ct.address(0x02133360),
        .screen = .top,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b,
    },
    .{
        .label = "friends win data",
        .ent_count = 8,
        .address = ct.address(0x02132be8), // note to self: I think theres more sprite loading hapening here when this gets loaded
        .screen = .top,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b, // palette might be wrong
    },
    .{
        .label = "hangar win data",
        .ent_count = 6,
        .address = ct.address(0x02132d28),
        .screen = .top,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b,
    },
    .{
        .label = "hangar win data 2",
        .ent_count = 8,
        .address = ct.address(0x02132e18),
        .screen = .top,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b,
    },
    .{
        .label = "level select top screen",
        .ent_count = 1,
        .address = ct.address(0x021331a8),
        .screen = .top,
        .file_name = "select_data.bin",
        .palette_fid = 7,
    },
    .{
        .label = "level select bottom screen",
        .ent_count = 0xc,
        .address = ct.address(0x021331bc),
        .screen = .bottom,
        .file_name = "select_data.bin",
        .palette_fid = 7,
    },
    .{
        .label = "data read failure 1",
        .ent_count = 1,
        .address = ct.address(0x021335ac),
        .screen = .bottom,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b,
    },
    .{
        .label = "data read failure 2",
        .ent_count = 1,
        .address = ct.address(0x021335be),
        .screen = .bottom,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b,
    },
    .{
        .label = "name entry? win",
        .ent_count = 9,
        .address = ct.address(0x02133600),
        .screen = .bottom,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b,
    },
    .{
        .label = "paint data",
        .ent_count = 7,
        .address = ct.address(0x02133c34),
        .screen = .bottom,
        .file_name = "paint_data.bin",
        .palette_fid = 0x1d,
    },
    .{
        .label = "unknown win data",
        .ent_count = 5,
        .address = ct.address(0x2133d78),
        .screen = .bottom,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b, // palette might be wrong here
    },
    .{
        .label = "unknown win data",
        .ent_count = 8,
        .address = ct.address(0x02133dd4),
        .screen = .bottom,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b, // palette might be wrong here
    },
    .{
        .label = "unknown win data",
        .ent_count = 1,
        .address = ct.address(0x02133d24),
        .screen = .bottom,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b, // palette might be wrong here
    },
    .{
        .label = "unknown win data",
        .ent_count = 4,
        .address = ct.address(0x021349c8),
        .screen = .bottom,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b, // palette might be wrong here
    },
    .{
        .label = "back to town top screen",
        .ent_count = 4,
        .address = ct.address(0x02133f34),
        .screen = .top,
        .file_name = "result_data.bin",
        .palette_fid = 0x21,
    },
    .{
        .label = "back to town bottom screen",
        .ent_count = 4,
        .address = ct.address(0x02133f7c),
        .screen = .bottom,
        .file_name = "result_data.bin",
        .palette_fid = 0x21,
    },
    .{
        .label = "unknown win data",
        .ent_count = 0x12,
        .address = ct.address(0x02134268),
        .screen = .top,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b, // palette might be wrong here
    },
    .{
        .label = "unknown win data",
        .ent_count = 0x11,
        .address = ct.address(0x02134468),
        .screen = .top,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b, // palette might be wrong here
    },
    .{
        .label = "unknown win data",
        .ent_count = 9,
        .address = ct.address(0x0213471c),
        .screen = .top,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b, // palette might be wrong here
    },
    .{
        .label = "unknown win data",
        .ent_count = 0xb,
        .address = ct.address(0x021348c0),
        .screen = .top,
        .file_name = "win_data.bin",
        .palette_fid = 0x5b, // palette might be wrong here
    },
};
