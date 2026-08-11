const std = @import("std");
const graphics = @import("graphics/graphics.zig");
const ct = @import("comptime_util.zig");
const FS = @import("FS/FS.zig");

pub const ent_res_entry = extern struct {
    x: u16,
    y: u16,
    oam_file_id: u16,
    tiles_file_id: u16,

    //something to do with animations
    flags: u16,
    flags2: u16,
    flags3: u16,
    flags4: u16,
    unknown: u16,
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
    screen: graphics.nds_types.Screen,
    compressed: bool = false,
    file_name: []const u8,
    palette_fid: u16,

    pub fn load_sprites(self: *const ent_res_list, rom: FS.rom, allocator: std.mem.Allocator) ![]?graphics.rs_types.packedOAMsprite {
        const rom_file = rom.files.get(self.file_name);
        if (rom_file) |file| {
            const unpacked = try file.unpack(allocator);
            const palettes: []align(1) const graphics.nds_types.Palette16 = @ptrCast(unpacked[self.palette_fid]);

            const entries: []align(1) const ent_res_entry = @ptrCast(rom.data[self.address..][0 .. self.ent_count * @sizeOf(ent_res_entry)]); //try allocator.alloc(ent_res_entry, self.ent_count);

            var sprites = try allocator.alloc(?graphics.rs_types.packedOAMsprite, self.ent_count);

            for (entries, 0..) |entry, i| {
                if (entry.tiles_file_id > unpacked.len) {
                    sprites[i] = null;
                    continue;
                }
                const tiles: []align(1) const graphics.nds_types.Tile = @ptrCast(unpacked[entry.tiles_file_id]);

                sprites[i] = try graphics.rs_types.packedOAMsprite.read(allocator, unpacked[entry.oam_file_id], tiles, palettes); //parser.read_ent_gx_data(&rom_file, @constCast(&entry), self.screen, allocator, palette);
            }

            return sprites;
        }
        return error.FileNotFound;
    }
};

// TODO: this might be getting replaced since I now know entities have a pointer to their resources
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
        .label = "level select top",
        .ent_count = 1,
        .address = ct.address(0x021331a8),
        .screen = .top,
        .file_name = "select_data.bin",
        .palette_fid = 7,
    },
    .{
        .label = "level select bottom",
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
        .label = "back to town top",
        .ent_count = 4,
        .address = ct.address(0x02133f34),
        .screen = .top,
        .file_name = "result_data.bin",
        .palette_fid = 0x21,
    },
    .{
        .label = "back to town bottom",
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
