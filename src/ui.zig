const sdl3 = @import("sdl3");
const std = @import("std");
const ent = @import("rom/ent.zig");
const graphics = @import("rom/graphics.zig");
const parsing = @import("rom/parsing.zig");
const FS = @import("rom/FS/FS.zig");

const FontSize = 14;

var root: uiRoot = undefined;

pub fn init(renderer: *sdl3.render.Renderer, allocator: *std.mem.Allocator) !void {
    const exe_dir = try std.fs.selfExeDirPathAlloc(allocator.*);
    const paths = [2][]const u8{ exe_dir, "JetBrainsMono-Regular.ttf" };
    const font_path = try std.fs.path.joinZ(allocator.*, &paths);
    root = .{
        .font = try sdl3.ttf.Font.init(font_path, FontSize),
        .renderer = renderer,
        .textEngine = try sdl3.ttf.RendererTextEngine.init(renderer.*),
        .allocator = allocator,
    };

    try refresh();
}

pub fn refresh() !void {
    const size = try root.renderer.getOutputSize();

    root.panels = .{
        .{
            .color = rgb(48, 52, 70),
            .rect = .{ .x = 0, .y = 0, .w = @floatFromInt(size.@"0"), .h = 32 },
        },
        .{
            .color = rgb(35, 38, 52),
            .rect = .{ .x = @floatFromInt(@divFloor(size.@"0", 4)), .y = 32, .w = @floatFromInt(size.@"0" - @divFloor(size.@"0", 4)), .h = @floatFromInt(size.@"1" - 32) },
        },
        .{
            .color = rgb(41, 44, 60),
            .rect = .{ .x = 0, .y = 32, .w = @floatFromInt(@divFloor(size.@"0", 4)), .h = @floatFromInt(size.@"1" - 32) },
        },
    };
}

var cur_action: ?*const fn () anyerror!void = null;

pub fn render(allocator: *std.mem.Allocator) !void {
    try root.drawOutline();
    try root.updateTopBar();

    const cursor = sdl3.mouse.getState();

    for (ent.ent_res_entry_lists, 0..) |list, i| {
        if (cursor.@"1" < root.panels[2].rect.w and cursor.@"2" > @as(f32, @floatFromInt(i * 24 + 32)) and cursor.@"2" < @as(f32, @floatFromInt((i + 1) * 24 + 32))) {
            try root.renderer.setDrawColor(rgb(65, 69, 89));
            try root.renderer.renderFillRect(.{
                .x = 4,
                .y = @as(f32, @floatFromInt(i)) * 24 + 32 + 6,
                .w = root.panels[2].rect.w - 8,
                .h = 21,
            });

            if (cursor.@"0".left and root.overlayActive == false and delay == 0) {
                oam_sprites = try list.load_sprites(allocator);
                oam_list = &list;
                screen = list.screen;
                sprite_num = 0;
                frame_num = 0;
                cur_action = &OamSpriteView;
                delay = 20;
            }
        }

        try root.panels[2].relativeText(list.label, .topleft, 16, @as(f32, @floatFromInt(i)) * 24 + 6);
    }

    if (cur_action != null) try cur_action.?();

    if (delay > 0) {
        delay -= 1;
    }
}

fn rgb(r: comptime_int, g: comptime_int, b: comptime_int) sdl3.pixels.Color {
    return .{ .r = r, .g = g, .b = b, .a = 255 };
}

fn rgba(r: comptime_int, g: comptime_int, b: comptime_int, a: comptime_int) sdl3.pixels.Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
}

fn dummy() void {}

const uiRoot = struct {
    font: sdl3.ttf.Font,
    renderer: *sdl3.render.Renderer,
    textEngine: sdl3.ttf.RendererTextEngine,
    allocator: *std.mem.Allocator,

    overlayActive: bool = false,

    panels: [3]Panel = std.mem.zeroes([3]Panel),

    topbar: TopBarType = .{
        .droplabels = [2][]const u8{
            "File",
            "About",
        },
    },

    pub fn drawOutline(self: *uiRoot) !void {
        for (self.panels) |panel| {
            try self.renderer.setDrawColor(panel.color);
            try self.renderer.renderFillRect(panel.rect);
        }
    }

    pub fn drawText(self: *uiRoot, text: []const u8, x: f32, y: f32) !void {
        const rendtext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&self.textEngine)).*, self.font, text);
        try rendtext.setColor(198, 208, 245, 255);
        try sdl3.ttf.drawRendererText(rendtext, x, y);
    }

    pub fn updateTopBar(self: *uiRoot) !void {
        const cursor = sdl3.mouse.getState();

        for (self.topbar.droplabels, 0..) |text, i| {
            const rendtext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&self.textEngine)).*, self.font, text);
            try rendtext.setColor(198, 208, 245, 255);

            if (cursor.@"2" < 32 and cursor.@"1" > @as(f32, @floatFromInt(i * 48)) and cursor.@"1" < @as(f32, @floatFromInt((i + 1) * 48))) {
                try self.renderer.setDrawColor(rgb(65, 69, 89));
                try self.renderer.renderFillRect(.{
                    .x = @floatFromInt(12 + (i * 48)),
                    .y = 4,
                    .w = @floatFromInt((try rendtext.getSize()).@"0" + 8),
                    .h = 24,
                });

                if (cursor.@"0".left and root.overlayActive == false) {
                    std.log.info("clicked {s}", .{text});
                }
            }

            try sdl3.ttf.drawRendererText(rendtext, @floatFromInt(i * 48 + 16), @floatFromInt(7));
        }
    }
};

const Corner = enum {
    topleft,
    topright,
    bottomleft,
    bottomright,
};

const Panel = struct {
    color: sdl3.pixels.Color,
    rect: sdl3.rect.Rect(f32),

    pub fn relativeRect(self: *Panel, corner: Corner, x: f32, y: f32, w: f32, h: f32) sdl3.rect.Rect(f32) {
        return switch (corner) {
            .topleft => .{ .x = x + self.rect.x, .y = y + self.rect.y, .w = w, .h = h },
            .topright => .{ .x = -x + self.rect.x + self.rect.w, .y = y + self.rect.y, .w = w, .h = h },
            .bottomleft => .{ .x = x + self.rect.x, .y = -y + self.rect.y + self.rect.h, .w = w, .h = h },
            .bottomright => .{ .x = -x - self.rect.x + self.rect.w, .y = -y + self.rect.y + self.rect.h, .w = w, .h = h },
        };
    }

    pub fn relativePos(self: *Panel, corner: Corner, x: f32, y: f32) Pos {
        const xpos = if (corner == .topleft or corner == .bottomleft) self.rect.x + x else self.rect.x + self.rect.w - x;
        const ypos = if (corner == .topleft or corner == .topright) self.rect.y + y else self.rect.y + self.rect.h - y;
        return .{ .x = xpos, .y = ypos };
    }

    pub fn relativeText(self: *Panel, text: []const u8, corner: Corner, x: f32, y: f32) !void {
        const xpos = if (corner == .topleft or corner == .bottomleft) self.rect.x + x else self.rect.x + self.rect.w - x;
        const ypos = if (corner == .topleft or corner == .topright) self.rect.y + y else self.rect.y + self.rect.y - y;
        try root.drawText(text, xpos, ypos);
    }
};

const Pos = struct {
    x: f32,
    y: f32,
};

const TopBarType = struct {
    droplabels: [2][]const u8,
};

var oam_sprites: []graphics.Sprite = undefined;
var oam_list: *const ent.ent_res_list = undefined;
var screen: graphics.Screen = .bottom;
var sprite_num: usize = 0;
var sprite_changed = false;
var frame_num: usize = 0;
var zoom: usize = 1;

fn OamSpriteView() anyerror!void {
    //try root.panels[1].relativeText("pallete: ", .topleft, 16, 16);
    var pos: Pos = root.panels[1].relativePos(.topleft, 16, 16);
    const sntext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&root.textEngine)).*, root.font, "sprite:");
    try sntext.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(sntext, pos.x, pos.y);

    pos.x += @floatFromInt((try sntext.getSize()).@"0");

    const prevsn = sprite_num;
    pos.x += try NumInput(&sprite_num, 0, oam_sprites.len - 1, pos.x, pos.y) + 16;
    if (prevsn != sprite_num) frame_num = 0;

    const fntext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&root.textEngine)).*, root.font, "frame:");
    try fntext.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(fntext, pos.x, pos.y);

    pos.x += @floatFromInt((try fntext.getSize()).@"0");

    pos.x += try NumInput(&frame_num, 0, oam_sprites[sprite_num].oamData.frames.len - 1, pos.x, pos.y) + 16;

    const zoomtext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&root.textEngine)).*, root.font, "zoom:");
    try zoomtext.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(zoomtext, pos.x, pos.y);

    pos.x += @floatFromInt((try zoomtext.getSize()).@"0");

    _ = try NumInput(&zoom, 1, 20, pos.x, pos.y);

    var bpos: Pos = root.panels[1].relativePos(.bottomleft, 16, 64);
    const screentext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&root.textEngine)).*, root.font, if (screen == .top) "top screen" else "bottom screen");
    try screentext.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(screentext, bpos.x, bpos.y);

    if (oam_list.compressed) {
        const compressedtext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&root.textEngine)).*, root.font, " - tiles possibly compressed");
        try compressedtext.setColor(198, 208, 245, 255);
        try sdl3.ttf.drawRendererText(compressedtext, bpos.x + @as(f32, @floatFromInt((try screentext.getSize()).@"0")), bpos.y);
    }

    bpos.y += @floatFromInt((try screentext.getSize()).@"1" + 4);

    const filenametext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&root.textEngine)).*, root.font, oam_list.file_name);
    try filenametext.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(filenametext, bpos.x, bpos.y);

    bpos.x += @floatFromInt((try filenametext.getSize()).@"0" + 24);

    const fileIdLabel = "file indexes - ";

    const filetext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&root.textEngine)).*, root.font, fileIdLabel);
    try filetext.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(filetext, bpos.x, bpos.y);

    bpos.x += @floatFromInt((try filetext.getSize()).@"0");

    var buf: [10]u8 = undefined;

    const paltext = try std.fmt.bufPrint(&buf, "pal:{}", .{oam_list.palette_fid});
    bpos.x += try Button(&savePalette, paltext, bpos.x, bpos.y) + 8;
    const oamtext = try std.fmt.bufPrint(&buf, "oam:{}", .{oam_sprites[sprite_num].oam_id});
    bpos.x += try Button(&saveOam, oamtext, bpos.x, bpos.y) + 8;
    const tilestext = try std.fmt.bufPrint(&buf, "tiles:{}", .{oam_sprites[sprite_num].tiles_id});
    bpos.x += try Button(&saveTiles, tilestext, bpos.x, bpos.y) + 8;

    const surf = oam_sprites[sprite_num].createSurface(frame_num) catch |err| {
        var text: []const u8 = undefined;
        text = if (err == error.NoOamAttributes) "no data for selected frame" else "error loading sprite";

        const errPos = root.panels[1].relativePos(.topleft, 16, 48);

        const errtext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&root.textEngine)).*, root.font, text);
        try errtext.setColor(198, 208, 245, 255);
        try sdl3.ttf.drawRendererText(errtext, errPos.x, errPos.y);
        return;
    };
    const surf_tex = try root.renderer.createTextureFromSurface(surf);
    const surf_rect = root.panels[1].relativeRect(.topleft, 16, 48, @floatFromInt(surf.getWidth() * zoom), @floatFromInt(surf.getHeight() * zoom));
    try root.renderer.setDrawColor(rgb(81, 87, 109));
    try root.renderer.renderRect(surf_rect);
    try root.renderer.renderTexture(surf_tex, null, surf_rect);

    const brpos = root.panels[1].relativePos(.bottomright, 192, 64);
    _ = try Button(&saveFramePNG, "Save Frame as PNG", brpos.x, brpos.y);
}
fn saveFramePNG() anyerror!void {
    var buf: [30]u8 = undefined;
    const default_name = try std.fmt.bufPrintZ(&buf, "/{s}-{}-{}.png", .{ oam_list.label, sprite_num, frame_num });
    sdl3.dialog.showSaveFile(void, &saveFramePNGFileSelected, null, try root.renderer.getWindow(), null, default_name);
}

fn saveFramePNGFileSelected(_: ?*void, file_list: ?[]const [*:0]const u8, filter: ?usize, err: bool) void {
    const errs = sdl3.errors.get();
    if (errs != null) {
        std.log.err("error with file save dialog: {s}", .{errs.?});
        return;
    }
    if (file_list == null or file_list.?.len == 0 or std.mem.len(file_list.?[0]) == 0) return; // no file selected

    const surf = oam_sprites[sprite_num].createSurface(frame_num) catch {
        unreachable; // shouldn't ever error here cause the button shows up only if didn't error when displaying it
    };

    const file_path: [:0]const u8 = std.mem.span(file_list.?[0]);

    sdl3.image.savePng(surf, file_path) catch |perr| {
        std.log.err("failed to save png: {}", .{perr});
    };

    _ = filter;
    _ = err;
}

fn savePalette() anyerror!void {
    var buf: [30]u8 = undefined;
    const default_name = try std.fmt.bufPrintZ(&buf, "/pal:{}-{s}", .{ oam_list.palette_fid, oam_list.file_name });
    sdl3.dialog.showSaveFile(void, &savePaletteFileSelected, null, try root.renderer.getWindow(), null, default_name);
}

fn savePaletteFileSelected(_: ?*void, file_list: ?[]const [*:0]const u8, filter: ?usize, err: bool) void {
    const errs = sdl3.errors.get();
    if (errs != null) {
        std.log.err("error with file save dialog: {s}", .{errs.?});
        return;
    }
    if (file_list == null or file_list.?.len == 0 or std.mem.len(file_list.?[0]) == 0) return; // no file selected

    var romfile = FS.rom_archive.OpenFile(oam_list.file_name);

    const data = romfile.readIndexedRaw(root.allocator, oam_list.palette_fid) catch {
        return;
    };
    const file = std.fs.createFileAbsoluteZ(file_list.?[0], .{}) catch {
        return;
    };
    _ = file.write(data) catch {
        return;
    };
    file.close();

    _ = filter;
    _ = err;
}

fn saveOam() anyerror!void {
    var buf: [30]u8 = undefined;
    const default_name = try std.fmt.bufPrintZ(&buf, "/oam:{}-{s}", .{ oam_sprites[sprite_num].oam_id, oam_list.file_name });
    sdl3.dialog.showSaveFile(void, &saveOamFileSelected, null, try root.renderer.getWindow(), null, default_name);
}

fn saveOamFileSelected(_: ?*void, file_list: ?[]const [*:0]const u8, filter: ?usize, err: bool) void {
    const errs = sdl3.errors.get();
    if (errs != null) {
        std.log.err("error with file save dialog: {s}", .{errs.?});
        return;
    }
    if (file_list == null or file_list.?.len == 0 or std.mem.len(file_list.?[0]) == 0) return;

    var romfile = FS.rom_archive.OpenFile(oam_list.file_name);

    const data = romfile.readIndexedRaw(root.allocator, oam_sprites[sprite_num].oam_id) catch {
        return;
    };
    const file = std.fs.createFileAbsoluteZ(file_list.?[0], .{}) catch {
        return;
    };
    _ = file.write(data) catch {
        return;
    };
    file.close();

    _ = filter;
    _ = err;
}

fn saveTiles() anyerror!void {
    var buf: [30]u8 = undefined;
    const default_name = try std.fmt.bufPrintZ(&buf, "/tiles:{}-{s}", .{ oam_sprites[sprite_num].tiles_id, oam_list.file_name });
    sdl3.dialog.showSaveFile(void, &saveOamFileSelected, null, try root.renderer.getWindow(), null, default_name);
}

fn saveTilesFileSelected(_: ?*void, file_list: ?[]const [*:0]const u8, filter: ?usize, err: bool) void {
    const errs = sdl3.errors.get();
    if (errs != null) {
        std.log.err("error with file save dialog: '{s}'", .{errs.?});
        return;
    }
    if (file_list == null or file_list.?.len == 0 or std.mem.len(file_list.?[0]) == 0) return; // no file selected

    var romfile = FS.rom_archive.OpenFile(oam_list.file_name);

    const data = romfile.readIndexedRaw(root.allocator, oam_sprites[sprite_num].tiles_id) catch {
        return;
    };
    const file = std.fs.createFileAbsoluteZ(file_list.?[0], .{}) catch {
        return;
    };
    _ = file.write(data) catch {
        return;
    };
    file.close();

    _ = filter;
    _ = err;
}

var delay: usize = 0;

fn NumInput(value: *usize, min: usize, max: usize, x: f32, y: f32) !f32 {
    const mouse = sdl3.mouse.getState();

    const minus = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&root.textEngine)).*, root.font, "-");
    try minus.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(minus, x, y);

    const charWidth: f32 = @floatFromInt((try minus.getSize()).@"0");
    const charHeight: f32 = @floatFromInt((try minus.getSize()).@"1");

    var buf: [20]u8 = undefined;
    const numString = try std.fmt.bufPrint(&buf, "{}/{}", .{ value.*, max });

    const rendtext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&root.textEngine)).*, root.font, numString);
    try rendtext.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(rendtext, x + charWidth, y);

    const plusX: f32 = x + charWidth + @as(f32, @floatFromInt((try rendtext.getSize()).@"0"));

    const plus = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&root.textEngine)).*, root.font, "+");
    try plus.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(plus, plusX, y);

    if (delay == 0) {
        if (mouse.@"0".left == true and root.overlayActive == false) {
            if (mouse.@"1" > x and value.* > min and mouse.@"2" > y and mouse.@"1" < x + charWidth and mouse.@"2" < y + charHeight) {
                value.* -= 1;
                delay = 20;
            } else if (mouse.@"1" > plusX and value.* < max and mouse.@"2" > y and mouse.@"1" < plusX + charWidth and mouse.@"2" < y + charHeight) {
                value.* += 1;
                delay = 20;
            }
        }
    }

    return plusX + @as(f32, @floatFromInt((try plus.getSize()).@"0")) - x;
}

fn Button(action: *const fn () anyerror!void, text: []const u8, x: f32, y: f32) !f32 {
    const cursor = sdl3.mouse.getState();

    const rendtext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&root.textEngine)).*, root.font, text);
    try rendtext.setColor(198, 208, 245, 255);

    const textsize = try rendtext.getSize();

    if (cursor.@"2" > y and cursor.@"1" > x and cursor.@"1" < x + @as(f32, @floatFromInt(textsize.@"0")) and cursor.@"2" < y + @as(f32, @floatFromInt(textsize.@"1"))) {
        try root.renderer.setDrawColor(rgb(65, 69, 89));
        try root.renderer.renderFillRect(.{
            .x = x,
            .y = y,
            .w = @as(f32, @floatFromInt(textsize.@"0")),
            .h = 24,
        });

        if (delay == 0 and cursor.@"0".left and root.overlayActive == false) {
            delay = 20;
            try action();
        }
    } else {
        try root.renderer.setDrawColor(rgb(81, 87, 109));
        try root.renderer.renderFillRect(.{
            .x = x,
            .y = y,
            .w = @as(f32, @floatFromInt(textsize.@"0")),
            .h = 24,
        });
    }

    try sdl3.ttf.drawRendererText(rendtext, x, y);

    return @floatFromInt(textsize.@"0");
}
