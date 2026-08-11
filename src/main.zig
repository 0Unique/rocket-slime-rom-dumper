const std = @import("std");
const FS = @import("rom/FS/FS.zig");
const ent = @import("rom/ent.zig");
const dvui = @import("dvui");
const graphics = @import("rom/graphics/graphics.zig");
const area = @import("rom/area.zig");

const renderer = @import("rom/graphics/pixelformat_renderer.zig").renderer;

var scale: f32 = 1.0;
pub const dvui_app: dvui.App = .{
    .config = .{
        .options = .{
            .size = .{ .w = 800.0, .h = 600.0 },
            .min_size = .{ .w = 250.0, .h = 350.0 },
            .title = "DVUI App Example",
            .window_init_options = .{
                // Could set a default theme here
                //.theme = dvui.Theme.builtin.dracula,
            },
        },
    },
    .frameFn = appFrame,
    .initFn = appInit,
    .deinitFn = appDeinit,
};
pub const main = dvui.App.main;
pub const panic = dvui.App.panic;
pub const std_options: std.Options = .{
    .logFn = dvui.App.logFn,
};

var perm_arena: std.heap.ArenaAllocator = undefined;
var rom: ?FS.rom = null;
var area_files: []area.area_files = undefined;

pub fn appInit(win: *dvui.Window) !void {
    // Add your own bundled font files...:
    // try dvui.addFont("NOTO", @embedFile("../src/fonts/NotoSansKR-Regular.ttf"), null);

    // If you want a custom theme use something like this:
    const theme = switch (win.backend.preferredColorScheme() orelse .light) {
        .light => dvui.Theme.builtin.adwaita_light,
        .dark => dvui.Theme.builtin.adwaita_dark,
    };
    win.themeSet(theme);

    perm_arena = .init(std.heap.page_allocator);
}

pub fn appDeinit(_: *dvui.Window) void {
    perm_arena.deinit();
}

pub fn appFrame() !dvui.App.Result {
    {
        var scaler = dvui.scale(@src(), .{ .scale = &dvui.currentWindow().content_scale, .pinch_zoom = .global }, .{ .rect = .cast(dvui.windowRect()) });
        scaler.deinit();

        if (menu()) |res| return res;

        var scroll = dvui.scrollArea(@src(), .{}, .{ .expand = .both, .style = .window });
        defer scroll.deinit();

        if (content()) |res| return res;
    }
    return .ok;
}

var ent_res_viewer_enabled: bool = false;
var area_viewer_enabled: bool = false;

pub fn menu() ?dvui.App.Result {
    var hbox = dvui.box(@src(), .{ .dir = .horizontal }, .{ .style = .window, .background = true, .expand = .horizontal });
    defer hbox.deinit();

    var m = dvui.menu(@src(), .horizontal, .{});
    defer m.deinit();

    if (dvui.menuItemLabel(@src(), "File", .{ .submenu = true }, .{})) |r| {
        var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer fw.deinit();

        if (rom == null) {
            if (dvui.menuItemLabel(@src(), "Open Rom", .{}, .{ .expand = .horizontal }) != null) {
                const filename = dvui.dialogNativeFileOpen(dvui.currentWindow().arena(), .{
                    .title = "Open Rom",
                    .filters = &.{ "*.nds", "*.srl" },
                    .filter_description = "nds rom",
                }) catch |err| blk: {
                    dvui.log.debug("Could not open file dialog, got {any}", .{err});
                    break :blk null;
                };
                if (filename) |f| {
                    rom = FS.rom.open(dvui.io, f, perm_arena.allocator()) catch |err| {
                        std.log.err("failed to open rom: {}", .{err});
                        m.close();
                        return .ok;
                    };
                    area_files = area.area_files.load_non_tank(perm_arena.allocator(), rom.?) catch |err| {
                        std.log.err("failed to load area files: {}", .{err});
                        m.close();
                        return .ok;
                    };
                    change_selected_area(&area_files[0]);

                    selectedList = ent.ent_res_entry_lists[0];
                    ent_entries = selectedList.load_sprites(rom.?, perm_arena.allocator()) catch |err| {
                        std.log.err("failed to load entity sprites: {}", .{err});
                        m.close();
                        return .ok;
                    };

                    m.close();
                }
            }
        }

        if (dvui.backend.kind != .web) {
            if (dvui.menuItemLabel(@src(), "Exit", .{}, .{ .expand = .horizontal }) != null) {
                return .close;
            }
        }
    }
    if (rom != null) {
        if (dvui.menuItemLabel(@src(), "Tools", .{ .submenu = true }, .{})) |r| {
            var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
            defer fw.deinit();

            if (dvui.menuItemLabel(@src(), "entity resource viewer", .{}, .{ .expand = .horizontal }) != null) {
                ent_res_viewer_enabled = !ent_res_viewer_enabled;
                m.close();
            }

            if (dvui.menuItemLabel(@src(), "area viewer", .{}, .{ .expand = .horizontal }) != null) {
                area_viewer_enabled = !area_viewer_enabled;
                m.close();
            }
        }
    }

    if (dvui.menuItemLabel(@src(), "Theme", .{ .submenu = true }, .{})) |r| {
        var fw = dvui.floatingMenu(@src(), .{ .from = r }, .{});
        defer fw.deinit();
        for (dvui.Theme.builtins, 0..) |theme, i| {
            if (dvui.menuItemLabel(@src(), theme.name, .{}, .{ .expand = .horizontal, .id_extra = i }) != null) {
                dvui.currentWindow().themeSet(theme);
                m.close();
            }
        }
    }

    return null;
}

pub fn content() ?dvui.App.Result {
    if (ent_res_viewer_enabled) {
        if (ent_res_viewer()) |res| return res;
    }

    if (area_viewer_enabled) {
        if (area_viewer()) |res| return res;
    }
    return null;
}

fn error_msg(msg: []const u8) dvui.App.Result {
    dvui.dialog(@src(), .{}, .{ .message = msg });
    return .ok;
}

var selectedList: ent.ent_res_list = undefined;
var ent_entries: ?[]?graphics.rs_types.packedOAMsprite = null;
var selectedEnt: usize = 0;
var selectedFrame: usize = 0;

fn selectList(i: usize) void {
    selectedList = ent.ent_res_entry_lists[i];
    if (ent_entries) |ents| perm_arena.allocator().free(ents);
    selectedEnt = 0;
    selectedFrame = 0;
    ent_entries = selectedList.load_sprites(rom.?, perm_arena.allocator()) catch null;
}

pub fn ent_res_viewer() ?dvui.App.Result {
    var window = dvui.floatingWindow(@src(), .{}, .{ .max_size_content = .{ .h = 800, .w = 800 }, .min_size_content = .{ .h = 600, .w = 800 }, .expand = .horizontal });
    defer window.deinit();
    _ = dvui.windowHeader("entity resource viewer", "", &ent_res_viewer_enabled);

    var mainbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
    defer mainbox.deinit();

    var list = dvui.scrollArea(@src(), .{}, .{});
    for (ent.ent_res_entry_lists, 0..) |ent_res_list, i| {
        if (dvui.labelClick(@src(), "{s}", .{ent_res_list.label}, .{}, .{ .id_extra = i })) {
            selectList(i);
        }
    }
    list.deinit();

    var cbox = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .horizontal });
    defer cbox.deinit();
    dvui.label(@src(), "{s} - {} entities\n{s} screen", .{
        selectedList.file_name,
        selectedList.ent_count,
        @tagName(selectedList.screen),
    }, .{});
    var hbox1 = dvui.box(@src(), .{ .dir = .vertical }, .{});
    defer hbox1.deinit();
    if (ent_entries) |ents| {
        if (dvui.sliderEntry(@src(), "scale: {}", .{ .value = &scale, .interval = 1, .min = 1, .max = 10 }, .{})) {}
        const tres = incdecNumberBox(@src(), "entity:", usize, .{ .value = &selectedEnt, .min = 0, .max = selectedList.ent_count - 1 });
        if (tres.changed and tres.value == .Valid) {
            selectedFrame = 0;
        }
        if (ents[selectedEnt]) |entity| {
            _ = incdecNumberBox(@src(), "frame:", usize, .{
                .value = &selectedFrame,
                .min = 0,
                .max = ents[selectedEnt].?.frames.len - 1,
            });
            const texture = renderer.renderPackedOAM(entity, dvui.currentWindow().arena()) catch return null;

            const scaler = dvui.scale(@src(), .{ .scale = &scale }, .{});
            if (texture[selectedFrame]) |t| {
                _ = dvui.image(@src(), .{ .source = .{ .pixels = .{
                    .rgba = @ptrCast(t.texture.data),
                    .width = @truncate(t.width),
                    .height = @truncate(t.height),
                } } }, .{});

                if (dvui.button(@src(), "save as png", .{}, .{})) {
                    const mpath = dvui.dialogNativeFileSave(dvui.currentWindow().arena(), .{}) catch return error_msg("save file dialog failed");
                    if (mpath) |path| {
                        const file = std.Io.Dir.createFileAbsolute(dvui.io, path, .{}) catch return error_msg("failed to create file");
                        defer file.close(dvui.io);
                        const size: usize = @as(usize, t.width) * @as(usize, t.height);
                        const buffer = dvui.currentWindow().arena().alloc(u8, size) catch return error_msg("out of memory");
                        var writer = file.writer(dvui.io, buffer);
                        dvui.PNGEncoder.write(&writer.interface, @ptrCast(t.texture.data), @truncate(t.width), @truncate(t.height)) catch return error_msg("file write failed");
                        writer.end() catch return error_msg("file writer end fail");
                    }
                }
            } else dvui.labelNoFmt(@src(), "no texture data", .{}, .{});
            scaler.deinit();
        } else dvui.labelNoFmt(@src(), "no entity data", .{}, .{});
    }

    return null;
}

fn incdecNumberBox(src: std.builtin.SourceLocation, comptime label: []const u8, comptime T: type, init_opts: dvui.TextEntryNumberInitOptions(T)) dvui.TextEntryNumberResult(T) {
    var changed = false;

    var cbox = dvui.box(src, .{ .dir = .horizontal }, .{ .id_extra = 0 });
    defer cbox.deinit();
    dvui.labelNoFmt(src, label, .{ .align_y = 0.5 }, .{ .expand = .vertical, .id_extra = 1 });
    if (dvui.button(src, "<", .{}, .{ .id_extra = 2 }) and (init_opts.min == null or init_opts.value.?.* > init_opts.min.?)) {
        init_opts.value.?.* -= 1;
        changed = true;
    }
    var out = dvui.textEntryNumber(src, T, init_opts, .{ .max_size_content = .{ .h = 50, .w = 25 }, .id_extra = 3 });
    dvui.labelEx(src, "/{}", .{init_opts.max.?}, .{ .align_y = 0.5 }, .{ .expand = .vertical, .padding = .{}, .id_extra = 4 });
    if (dvui.button(src, ">", .{}, .{ .id_extra = 5 }) and (init_opts.min == null or init_opts.value.?.* < init_opts.max.?)) {
        init_opts.value.?.* += 1;
        changed = true;
    }

    if (changed) out.changed = true;

    return out;
}

var selectedArea: *area.area_files = undefined;

fn change_selected_area(new_area: *area.area_files) void {
    selectedArea = new_area;
    pal_i = 0;
}

var enabled_layers: [6]bool = [6]bool{ true, true, true, true, true, true };
var pal_i: usize = 0;

var canvas_scroll: dvui.ScrollInfo = .{ .horizontal = .auto, .vertical = .auto };

fn area_viewer() ?dvui.App.Result {
    var window = dvui.floatingWindow(@src(), .{}, .{ .max_size_content = .{ .h = 400, .w = 500 } });
    defer window.deinit();

    _ = dvui.windowHeader("area viewer", "", &area_viewer_enabled);
    var mainbox = dvui.box(@src(), .{ .dir = .horizontal }, .{});
    defer mainbox.deinit();

    var list = dvui.scrollArea(@src(), .{}, .{});
    for (area_files, 0..) |*entry, i| {
        if (dvui.labelClick(@src(), "{}: {s}", .{ i, "non tank battle" }, .{}, .{ .id_extra = i })) {
            change_selected_area(entry);
        }
    }
    list.deinit();

    var cbox = dvui.box(@src(), .{ .dir = .vertical }, .{ .expand = .horizontal });
    defer cbox.deinit();
    dvui.label(@src(), "size: {}x{} - {} maps", .{
        selectedArea.width,
        selectedArea.height,
        selectedArea.maps.len,
    }, .{});

    {
        var canvas = dvui.scrollArea(@src(), .{ .scroll_info = &canvas_scroll }, .{ .expand = .both });
        defer canvas.deinit();

        _ = incdecNumberBox(@src(), "palette:", usize, .{ .value = &pal_i, .min = 0, .max = selectedArea.palettes.len - 1 });

        const texture = renderer.nds_texture.create(selectedArea.width * 8, selectedArea.height * 8, dvui.currentWindow().arena()) catch return error_msg("out of memory");

        dvui.labelNoFmt(@src(), "layers", .{}, .{});
        for (selectedArea.maps, 0..) |map, i| {
            const map_i = @divFloor(i, 2);
            const str = std.fmt.allocPrint(dvui.currentWindow().arena(), "{} {s}", .{ map_i, if (i % 2 == 0) "top" else "bottom" }) catch return error_msg("out of memory");
            if (dvui.checkbox(@src(), &enabled_layers[i], str, .{ .id_extra = i })) {}
            if (enabled_layers[i]) renderer.renderMap(texture, 0, if ((i % 2) == 1) selectedArea.height * 8 / 2 else 0, map, selectedArea.tiles, selectedArea.palettes[pal_i]);
        }

        var iw = dvui.image(@src(), .{ .source = .{ .pixels = .{
            .rgba = @ptrCast(texture.texture.data),
            .width = selectedArea.width * 8,
            .height = selectedArea.height * 8,
        } } }, .{});

        if (dvui.button(@src(), "save as png", .{}, .{})) {
            const mpath = dvui.dialogNativeFileSave(dvui.currentWindow().arena(), .{}) catch return error_msg("save file dialog failed");
            if (mpath) |path| {
                const file = std.Io.Dir.createFileAbsolute(dvui.io, path, .{}) catch return error_msg("failed to create file");
                defer file.close(dvui.io);
                const size: usize = @as(usize, selectedArea.width) * 8 * @as(usize, selectedArea.height) * 8;
                const buffer = dvui.currentWindow().arena().alloc(u8, size) catch return error_msg("out of memory");
                var writer = file.writer(dvui.io, buffer);
                dvui.PNGEncoder.write(&writer.interface, @ptrCast(texture.texture.data), selectedArea.width * 8, selectedArea.height * 8) catch return error_msg("file write failed");
                writer.end() catch return error_msg("file writer end fail");
            }
        }

        const wd = &iw;
        for (dvui.events()) |*e| {
            if (e.evt != .mouse) continue;
            if (!dvui.eventMatchSimple(e, wd)) continue;
            const me = e.evt.mouse;

            switch (me.action) {
                .press => if (me.button.pointer()) {
                    e.handle(@src(), wd);
                    dvui.captureMouse(wd, e.num);
                    dvui.dragPreStart(me.button, me.p, .{ .cursor = .arrow_all });
                },
                .release => if (me.button.pointer()) {
                    e.handle(@src(), wd);
                    dvui.captureMouse(null, e.num);
                    dvui.dragEnd();
                },
                .motion => if (dvui.dragging(me.p, null)) |dp| {
                    e.handle(@src(), wd);

                    canvas_scroll.viewport.x -= dp.x / dvui.currentWindow().natural_scale;
                    canvas_scroll.viewport.y -= dp.y / dvui.currentWindow().natural_scale;
                },
                else => {},
            }
        }
    }

    return null;
}
