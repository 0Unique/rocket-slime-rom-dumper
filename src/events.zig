const sdl3 = @import("sdl3");
pub const std = @import("std");
pub const ent = @import("rom/ent.zig");
pub const graphics = @import("rom/graphics.zig");
pub const parsing = @import("rom/parsing.zig");
pub const FS = @import("rom/FS/FS.zig");
pub const ui = @import("ui.zig");

pub var top_bar: TopBar = .{};

pub var side_panel_fill_event: ?UiEvent = null;
pub var view_event: ?UiEvent = null;
pub var display_event: ?UiEvent = null;
pub var dropdown_event: ?UiEvent = null;

pub const UiEvent = struct {
    run: *const fn (*anyopaque) void,
    prio: Priorities,
    type: Types = .default,
    data: *anyopaque = undefined,
};

pub const Priorities = enum {
    refresh,
    draw_panels,
    view,
    side_panel_input,
    side_panel,
    top_panel,
    main_panel,
    dropdown,
};

pub const Types = enum {
    default,
    input,
};

pub const WindowSizeChanged: UiEvent = .{
    .prio = .refresh,
    .run = &Funcs.ResizePanels,
};

pub const DrawPanelsEvent: UiEvent = .{
    .prio = .draw_panels,
    .run = &Funcs.DrawPanels,
};

pub const TopPanelUpdateEvent: UiEvent = .{
    .prio = .top_panel,
    .run = &Funcs.TopPanelUpdate,
};

pub const PopupEvent: UiEvent = .{
    .prio = .top_panel,
    .type = .input,
    .run = &Funcs.Popup,
};

pub const OpenRomEvent: UiEvent = .{
    .prio = .refresh,
    .type = .default,
    .run = &Funcs.OpenRom,
};

pub const StartupEvent: UiEvent = .{
    .prio = .refresh,
    .type = .default,
    .run = &Funcs.Startup,
};

pub const RomLoadedEvent: UiEvent = .{
    .prio = .top_panel,
    .type = .default,
    .run = &Funcs.RomOpened,
};

pub var OamSpriteViewEvent: UiEvent = .{
    .prio = .view,
    .type = .default,
    .run = &Funcs.OamSpriteView,
};

pub const SwitchViewEvent: UiEvent = .{
    .prio = .top_panel,
    .type = .default,
    .run = @ptrCast(&Funcs.SwitchView), // this might cause problems on some systems, if it does then it'll need to be changed, but it really shouldn't on most modern systems.
};

pub const DrawSideBarListInputEvent: UiEvent = .{
    .prio = .side_panel_input,
    .type = .input,
    .run = @ptrCast(&Funcs.DrawSideBarListInput), // this might cause problems on some systems, if it does then it'll need to be changed, but it really shouldn't on most modern systems.
};

pub const DrawSideBarListEvent: UiEvent = .{
    .prio = .side_panel,
    .type = .default,
    .run = @ptrCast(&Funcs.DrawSideBarList), // this might cause problems on some systems, if it does then it'll need to be changed, but it really shouldn't on most modern systems.
};

pub const LoadOamSpriteDisplayEvent: UiEvent = .{
    .prio = .main_panel,
    .type = .default,
    .run = @ptrCast(&Funcs.LoadOamSpriteDisplay), // this might cause problems on some systems, if it does then it'll need to be changed, but it really shouldn't on most modern systems.
};

pub const OamSpriteDisplayEvent: UiEvent = .{
    .prio = .main_panel,
    .type = .default,
    .run = @ptrCast(&Funcs.OamSpriteDisplay), // this might cause problems on some systems, if it does then it'll need to be changed, but it really shouldn't on most modern systems.
};

pub const StartDropdownEvent: UiEvent = .{
    .prio = .top_panel,
    .type = .default,
    .run = @ptrCast(&Funcs.StartDropdown), // this might cause problems on some systems, if it does then it'll need to be changed, but it really shouldn't on most modern systems.
};

pub const DropdownEvent: UiEvent = .{
    .prio = .dropdown,
    .type = .default,
    .run = @ptrCast(&Funcs.Dropdown), // this might cause problems on some systems, if it does then it'll need to be changed, but it really shouldn't on most modern systems.
};

pub const Funcs = struct {
    fn ResizePanels(_: *anyopaque) void {
        ui.top_panel.rect = ui.top_panel.get_rect();
        ui.main_panel.rect = ui.main_panel.get_rect();
        ui.side_panel.rect = ui.side_panel.get_rect();
    }

    fn DrawPanels(_: *anyopaque) void {
        ui.main_panel.draw() catch {
            std.log.err("Failed to draw main panel", .{});
        };
        ui.side_panel.draw() catch {
            std.log.err("Failed to draw side panel", .{});
        };
    }

    fn TopPanelUpdate(_: *anyopaque) void {
        ui.top_panel.draw() catch {
            std.log.err("Failed to draw top panel", .{});
        };

        const cursor = sdl3.mouse.getState();

        if (dropdown_event) |_| {
            ui.supress_inputs = true;
        }

        for (top_bar.item_list.items, 0..) |item, i| {
            const rendtext = ui.renderText(item.label) catch {
                std.log.err("TopPanelUpdate - failed to draw text", .{});
                return;
            };

            if (cursor.@"2" < 32 and cursor.@"1" > @as(f32, @floatFromInt(i * 48)) and cursor.@"1" < @as(f32, @floatFromInt((i + 1) * 48))) {
                ui.renderer.setDrawColor(ui.rgb(65, 69, 89)) catch {
                    std.log.err("TopPanelUpdate - failed to set draw color", .{});
                    return;
                };

                var pos: struct { f32, f32 } = .{ @floatFromInt(12 + (i * 48)), 7 };

                ui.renderer.renderFillRect(.{
                    .x = pos.@"0",
                    .y = pos.@"1",
                    .w = @floatFromInt((rendtext.getSize() catch .{ 0, 0 }).@"0" + 8),
                    .h = 21,
                }) catch {
                    std.log.err("TopPanelUpdate - failed to draw rect", .{});
                    return;
                };

                if (ui.mouse_clicked) {
                    pos.@"1" = 32;
                    var event = DropdownEvent;
                    var dropdown_item = ui.allocator.create(TopBarItems) catch {
                        std.log.err("allocation failed", .{});
                        return;
                    };
                    dropdown_item.* = item;
                    dropdown_item.pos = pos;
                    event.data = @ptrCast(dropdown_item);
                    dropdown_event = event;
                }
            }

            ui.drawRenderedText(rendtext, @floatFromInt(i * 48 + 16), @floatFromInt(7)) catch {
                std.log.err("failed to draw text", .{});
                return;
            };
        }
    }

    fn OpenRom(_: *anyopaque) void {
        sdl3.dialog.showOpenFile(void, &rom_file_chosen, null, ui.renderer.getWindow() catch {
            std.log.err("failed to get window for OpenRom", .{});
            return;
        }, null, null, false);
    }

    fn Startup(_: *anyopaque) void {
        top_bar.init();
    }

    var rom_loaded = false;
    fn rom_file_chosen(_: ?*void, file_list: ?[]const [*:0]const u8, filter: ?usize, err: bool) void {
        const errs = sdl3.errors.get();
        if (errs) |errt| {
            std.log.err("error with file open dialog: {s}", .{errt});
            return;
        }
        if (file_list == null or file_list.?.len == 0 or std.mem.len(file_list.?[0]) == 0) return; // no file selected

        const file_path: []const u8 = std.mem.span(file_list.?[0]);

        _ = filter;
        _ = err;

        rom_loaded = FS.init(file_path, ui.allocator);
        ui.add_event(RomLoadedEvent);
    }

    fn RomOpened(_: *anyopaque) void {
        top_bar.item_list.append(ui.allocator, .{
            .label = "View",
            .dropitems = &view_dropdown,
        }) catch {
            std.log.err("failed to add item to top bar", .{});
        };
    }

    fn SwitchView(event: *UiEvent) void {
        view_event = event.*;
    }

    fn StartDropdown(event: *UiEvent) void {
        dropdown_event = event.*;
    }

    fn Dropdown(item: *TopBarItems) void {
        const mouse = sdl3.mouse.getState();

        var clicked_outside_dropdown = false;

        for (item.*.dropitems, 0..) |dropitem, i| {
            const text = ui.renderText(dropitem.label) catch {
                std.log.err("failed to render text: {s}", .{dropitem.label});
                return;
            };
            const textsize = text.getSize() catch .{ 0, 0 };
            ui.renderer.setDrawColor(ui.rgb(65, 69, 89)) catch {
                std.log.err("TopPanelUpdate - failed to set draw color", .{});
                return;
            };

            const posY: f32 = item.pos.@"1" + @as(f32, @floatFromInt(i * 30));

            if (mouse.@"1" > item.pos.@"0" and mouse.@"1" < item.pos.@"0" + 128 and mouse.@"2" > posY and mouse.@"2" < posY + @as(f32, @floatFromInt(textsize.@"1" + 12))) {
                if (ui.mouse_clicked) {
                    var event = dropitem.event;
                    event.data = dropitem.data;
                    ui.add_event(event);
                    ui.allocator.destroy(item);
                    dropdown_event = null;
                }
                ui.renderer.setDrawColor(ui.rgb(81, 87, 109)) catch {
                    std.log.err("TopPanelUpdate - failed to set draw color", .{});
                    return;
                };
            } else {
                if (ui.mouse_clicked) clicked_outside_dropdown = true;
                ui.renderer.setDrawColor(ui.rgb(65, 69, 89)) catch {
                    std.log.err("TopPanelUpdate - failed to set draw color", .{});
                    return;
                };
            }
            ui.renderer.renderFillRect(.{
                .x = item.pos.@"0",
                .y = posY,
                .w = 128,
                .h = @floatFromInt(textsize.@"1" + 12),
            }) catch {
                std.log.err("TopPanelUpdate - failed to draw rect", .{});
                return;
            };
            ui.drawRenderedText(text, item.pos.@"0" + 6, item.pos.@"1" + @as(f32, @floatFromInt(i * 30 + 5))) catch {
                std.log.err("failed to render text: {s}", .{dropitem.label});
                return;
            };
        }
        if (clicked_outside_dropdown) {
            ui.allocator.destroy(item);
            dropdown_event = null;
        }
    }

    fn OamSpriteView(_: *anyopaque) void {
        const side_bar_list: *SidePanelList = ui.allocator.create(SidePanelList) catch {
            std.log.err("allocation error", .{});
            return;
        };
        const list: []SidePanelItem = ui.allocator.alloc(SidePanelItem, ent.ent_res_entry_lists.len) catch {
            std.log.err("allocation error", .{});
            return;
        };
        for (0..ent.ent_res_entry_lists.len) |i| {
            list[i].label = ent.ent_res_entry_lists[i].label;
            var event = LoadOamSpriteDisplayEvent; // clicked side bar
            event.data = @ptrCast(@constCast(&ent.ent_res_entry_lists[i]));
            list[i].event = event;
        }
        side_bar_list.item_list = list;
        var input_event = DrawSideBarListInputEvent;
        input_event.data = @ptrCast(side_bar_list);
        var event = DrawSideBarListEvent;
        event.data = @ptrCast(side_bar_list); // might not be needed?
        ui.add_event(input_event);
        ui.add_event(event);
    }

    var scrollAmount: f32 = 0;
    fn DrawSideBarListInput(list: *SidePanelList) void {
        const cursor = sdl3.mouse.getState();
        if (ui.mouse_scroll + scrollAmount > 0 and ui.mouse_scroll + scrollAmount < @as(f32, @floatFromInt((list.item_list.len - 1) * 24)) and cursor.@"1" < ui.side_panel.rect.w)
            scrollAmount += ui.mouse_scroll;

        for (list.item_list, 0..) |item, i| {
            if (cursor.@"1" < ui.side_panel.rect.w and cursor.@"2" > 32 and cursor.@"2" > @as(f32, @floatFromInt(i * 24 + 32)) - scrollAmount and cursor.@"2" < @as(f32, @floatFromInt((i + 1) * 24 + 32)) - scrollAmount) {
                ui.renderer.setDrawColor(ui.rgb(65, 69, 89)) catch {
                    std.log.err("set draw color failed", .{});
                    return;
                };
                ui.renderer.renderFillRect(.{
                    .x = 4,
                    .y = @as(f32, @floatFromInt(i)) * 24 + 32 + 6 - scrollAmount,
                    .w = ui.side_panel.rect.w - 8,
                    .h = 21,
                }) catch {
                    std.log.err("draw rect failed", .{});
                    return;
                };

                if (ui.mouse_clicked) {
                    ui.add_event(item.event);
                }
            }
        }
    }
    fn DrawSideBarList(list: *SidePanelList) void {
        for (list.item_list, 0..) |item, i| {
            ui.side_panel.relativeText(item.label, .topleft, 16, @as(f32, @floatFromInt(i)) * 24 + 6 - scrollAmount) catch {
                std.log.err("relative text failed", .{});
            };
        }
        ui.allocator.free(list.item_list);
        ui.allocator.destroy(list);
    }

    var sprite_num: usize = 0;
    var frame_num: usize = 0;
    var zoom: usize = 1;
    var oam_list: *ent.ent_res_list = undefined;
    var oam_sprites: []graphics.Sprite = undefined;
    fn LoadOamSpriteDisplay(list: *ent.ent_res_list) void {
        var event = OamSpriteDisplayEvent;
        event.data = @ptrCast(list);
        oam_list = list;
        oam_sprites = list.load_sprites(ui.allocator) catch return;
        display_event = event;
        sprite_num = 0;
        frame_num = 0;
    }

    fn OamSpriteDisplay(list: *ent.ent_res_list) void {
        var pos = ui.main_panel.relativePos(.topleft, 16, 16);
        const sntext = sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&ui.textEngine)).*, ui.font, "sprite:") catch return;
        sntext.setColor(198, 208, 245, 255) catch return;
        sdl3.ttf.drawRendererText(sntext, pos.@"0", pos.@"1") catch return;
        pos.@"0" += @floatFromInt((sntext.getSize() catch .{ 0, 0 }).@"0");

        const prevsn = sprite_num;
        pos.@"0" += (ui.NumInput(&sprite_num, 0, oam_sprites.len - 1, pos.@"0", pos.@"1") catch return) + 16;
        if (prevsn != sprite_num) frame_num = 0;

        const fntext = sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&ui.textEngine)).*, ui.font, "frame:") catch return;
        fntext.setColor(198, 208, 245, 255) catch {
            return;
        };
        sdl3.ttf.drawRendererText(fntext, pos.@"0", pos.@"1") catch {
            return;
        };

        pos.@"0" += @floatFromInt((fntext.getSize() catch return).@"0");

        pos.@"0" += (ui.NumInput(&frame_num, 0, oam_sprites[sprite_num].oamData.frames.len - 1, pos.@"0", pos.@"1") catch
            return) + 16;

        const zoomtext = sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&ui.textEngine)).*, ui.font, "zoom:") catch {
            return;
        };
        zoomtext.setColor(198, 208, 245, 255) catch {
            return;
        };
        sdl3.ttf.drawRendererText(zoomtext, pos.@"0", pos.@"1") catch {
            return;
        };

        pos.@"0" += @floatFromInt((zoomtext.getSize() catch {
            return;
        }).@"0");

        _ = ui.NumInput(&zoom, 1, 20, pos.@"0", pos.@"1") catch {
            return;
        };

        var bpos = ui.main_panel.relativePos(.bottomleft, 16, 64);
        const screentext = sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&ui.textEngine)).*, ui.font, if (list.screen == .top) "top screen" else "bottom screen") catch {
            return;
        };
        screentext.setColor(198, 208, 245, 255) catch {
            return;
        };
        sdl3.ttf.drawRendererText(screentext, bpos.@"0", bpos.@"1") catch {
            return;
        };

        if (list.compressed) {
            const compressedtext = sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&ui.textEngine)).*, ui.font, " - tiles possibly compressed") catch {
                return;
            };
            compressedtext.setColor(198, 208, 245, 255) catch {
                return;
            };
            sdl3.ttf.drawRendererText(compressedtext, bpos.@"0" + @as(f32, @floatFromInt((screentext.getSize() catch return).@"0")), bpos.@"1") catch {
                return;
            };
        }

        bpos.@"1" += @floatFromInt((screentext.getSize() catch {
            return;
        }).@"1" + 4);

        const filenametext = sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&ui.textEngine)).*, ui.font, list.file_name) catch {
            return;
        };
        filenametext.setColor(198, 208, 245, 255) catch {
            return;
        };
        sdl3.ttf.drawRendererText(filenametext, bpos.@"0", bpos.@"1") catch {
            return;
        };

        bpos.@"0" += @floatFromInt((filenametext.getSize() catch {
            return;
        }).@"0" + 24);

        const fileIdLabel = "file indexes - ";

        const filetext = sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&ui.textEngine)).*, ui.font, fileIdLabel) catch {
            return;
        };
        filetext.setColor(198, 208, 245, 255) catch {
            return;
        };
        sdl3.ttf.drawRendererText(filetext, bpos.@"0", bpos.@"1") catch {
            return;
        };

        bpos.@"0" += @floatFromInt((filetext.getSize() catch {
            return;
        }).@"0");

        var buf: [10]u8 = undefined;

        const paltext = std.fmt.bufPrint(&buf, "pal:{}", .{list.palette_fid}) catch {
            return;
        };
        bpos.@"0" += (ui.Button(&savePalette, paltext, bpos.@"0", bpos.@"1") catch return) + 8;
        const oamtext = std.fmt.bufPrint(&buf, "oam:{}", .{oam_sprites[sprite_num].oam_id}) catch {
            return;
        };
        bpos.@"0" += (ui.Button(&saveOam, oamtext, bpos.@"0", bpos.@"1") catch
            return) + 8;
        const tilestext = std.fmt.bufPrint(&buf, "tiles:{}", .{oam_sprites[sprite_num].tiles_id}) catch {
            return;
        };
        bpos.@"0" += (ui.Button(&saveTiles, tilestext, bpos.@"0", bpos.@"1") catch return) + 8;

        const surf = oam_sprites[sprite_num].createSurface(frame_num) catch |err| {
            var text: []const u8 = undefined;
            text = if (err == error.NoOamAttributes) "no data for selected frame" else "error loading sprite";

            const errPos = ui.main_panel.relativePos(.topleft, 16, 48);

            const errtext = sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&ui.textEngine)).*, ui.font, text) catch {
                return;
            };
            errtext.setColor(198, 208, 245, 255) catch {
                return;
            };
            sdl3.ttf.drawRendererText(errtext, errPos.@"0", errPos.@"1") catch {
                return;
            };
            return;
        };
        const surf_tex = ui.renderer.createTextureFromSurface(surf) catch {
            return;
        };
        const surf_rect = ui.main_panel.relativeRect(.topleft, 16, 48, @floatFromInt(surf.getWidth() * zoom), @floatFromInt(surf.getHeight() * zoom));
        ui.renderer.setDrawColor(ui.rgb(81, 87, 109)) catch {
            return;
        };
        ui.renderer.renderRect(surf_rect) catch {
            return;
        };
        ui.renderer.renderTexture(surf_tex, null, surf_rect) catch {
            return;
        };

        const brpos = ui.main_panel.relativePos(.bottomright, 192, 64);
        _ = ui.Button(&saveFramePNG, "Save Frame as PNG", brpos.@"0", brpos.@"1") catch {
            return;
        };
    }

    fn saveFramePNG() anyerror!void {
        var buf: [30]u8 = undefined;
        const default_name = try std.fmt.bufPrintZ(&buf, "/{s}-{}-{}.png", .{ oam_list.label, sprite_num, frame_num });
        sdl3.dialog.showSaveFile(void, &saveFramePNGFileSelected, null, try ui.renderer.getWindow(), null, default_name);
    }

    fn saveFramePNGFileSelected(_: ?*void, file_list: ?[]const [*:0]const u8, filter: ?usize, err: bool) void {
        const errs = sdl3.errors.get();
        if (errs) |errt| {
            std.log.err("error with file save dialog: {s}", .{errt});
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
        sdl3.dialog.showSaveFile(void, &savePaletteFileSelected, null, try ui.renderer.getWindow(), null, default_name);
    }

    fn savePaletteFileSelected(_: ?*void, file_list: ?[]const [*:0]const u8, filter: ?usize, err: bool) void {
        const errs = sdl3.errors.get();
        if (errs) |errt| {
            std.log.err("error with file save dialog: {s}", .{errt});
            return;
        }
        if (file_list == null or file_list.?.len == 0 or std.mem.len(file_list.?[0]) == 0) return; // no file selected

        var romfile = FS.rom_archive.OpenFile(oam_list.file_name);

        const data = romfile.readIndexedRaw(ui.allocator, oam_list.palette_fid) catch {
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
        sdl3.dialog.showSaveFile(void, &saveOamFileSelected, null, try ui.renderer.getWindow(), null, default_name);
    }

    fn saveOamFileSelected(_: ?*void, file_list: ?[]const [*:0]const u8, filter: ?usize, err: bool) void {
        const errs = sdl3.errors.get();
        if (errs) |errt| {
            std.log.err("error with file save dialog: {s}", .{errt});
            return;
        }
        if (file_list == null or file_list.?.len == 0 or std.mem.len(file_list.?[0]) == 0) return;

        var romfile = FS.rom_archive.OpenFile(oam_list.file_name);

        const data = romfile.readIndexedRaw(ui.allocator, oam_sprites[sprite_num].oam_id) catch {
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
        sdl3.dialog.showSaveFile(void, &saveOamFileSelected, null, try ui.renderer.getWindow(), null, default_name);
    }

    fn saveTilesFileSelected(_: ?*void, file_list: ?[]const [*:0]const u8, filter: ?usize, err: bool) void {
        const errs = sdl3.errors.get();
        if (errs) |errt| {
            std.log.err("error with file save dialog: '{s}'", .{errt});
            return;
        }
        if (file_list == null or file_list.?.len == 0 or std.mem.len(file_list.?[0]) == 0) return; // no file selected

        var romfile = FS.rom_archive.OpenFile(oam_list.file_name);

        const data = romfile.readIndexedRaw(ui.allocator, oam_sprites[sprite_num].tiles_id) catch {
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
};
pub const SidePanelList = struct {
    item_list: []SidePanelItem,
};

pub const TopBarItems = struct {
    label: []const u8,
    dropitems: []DropDownItem,
    pos: struct { f32, f32 } = undefined,
};

pub const DropDownItem = struct {
    label: []const u8,
    event: UiEvent,
    data: *anyopaque = undefined,
};

pub const TopBar = struct {
    item_list: std.ArrayList(TopBarItems) = .empty,

    fn init(self: *TopBar) void {
        self.item_list.clearAndFree(ui.allocator);
        self.item_list.append(ui.allocator, .{
            .label = "File",
            .dropitems = &file_operations_dropdown,
        }) catch {
            std.log.err("failed to init top bar", .{});
        };
    }
};

pub var file_operations_dropdown: [1]DropDownItem = .{
    .{
        .label = "Open Rom",
        .event = OpenRomEvent,
    },
};

pub var view_dropdown: [1]DropDownItem = .{
    .{
        .label = "OAM OBJ Sprites",
        .event = SwitchViewEvent,
        .data = @ptrCast(&OamSpriteViewEvent),
    },
};

pub const SidePanelItem = struct {
    label: []const u8,
    event: UiEvent,
    x: f32,
    y: f32,

    fn onClick(self: *SidePanelItem) void {
        ui.add_event(self.event);
    }

    fn draw(self: *SidePanelItem) void {
        try ui.drawText(self.label, self.x, self.y);
    }
};
