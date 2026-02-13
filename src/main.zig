const builtin = @import("builtin");
const std = @import("std");
const archive = @import("rom/FS/archive.zig");
const FS = @import("rom/FS/FS.zig");
const parser = @import("rom/parsing.zig");
const graphics = @import("rom/graphics.zig");
const file = @import("rom/FS/file.zig");
const compression = @import("rom/compression.zig");
const ent = @import("rom/ent.zig");
const sdl3 = @import("sdl3");
const ui = @import("ui.zig");

const fps = 60;
const screen_width = 1024; // 256 + 64;
const screen_height = 768; // 384 + 64 * 2;

var allocator: std.mem.Allocator = undefined;
var renderer: sdl3.render.Renderer = undefined;
var arena: std.heap.ArenaAllocator = undefined;
var window: sdl3.video.Window = undefined;
const init_flags: sdl3.InitFlags = .{ .video = true };

var loaded = false;

pub fn main() !void {
    // required for opening file save/open dialogs on linux
    if (builtin.os.tag == .linux) try sdl3.hints.set(.file_dialog_driver, "zenity");
    arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    allocator = arena.allocator();

    sdl3.init(init_flags) catch {
        std.log.err("sdl3 init failed: {s}\n", .{sdl3.errors.get().?});
        return;
    };
    defer sdl3.quit(init_flags);
    defer sdl3.shutdown();
    sdl3.ttf.init() catch {
        std.log.err("ttf init failed: {s}\n", .{sdl3.errors.get().?});
        return;
    };

    window = try sdl3.video.Window.init("Rocket Slime Rom Dumper", screen_width, screen_height, .{ .resizable = true });
    defer window.deinit();

    renderer = try sdl3.render.Renderer.init(window, null);
    defer renderer.deinit();

    //sdl3.dialog.showOpenFile(void, &rom_file_chosen, null, window, null, null, false);

    // wait for FS loaded
    //while (loaded == false) {
    //sdl3.events.pump();
    //}
    //defer FS.deinit();

    try ui.init(&renderer, allocator);
    defer ui.deinit();

    while (!try ui.update()) {}
}

fn rom_file_chosen(_: ?*void, file_list: ?[]const [*:0]const u8, filter: ?usize, err: bool) void {
    const errs = sdl3.errors.get();
    if (errs != null) {
        std.log.err("error with file open dialog: {s}", .{errs.?});
        return;
    }
    if (file_list == null or file_list.?.len == 0 or std.mem.len(file_list.?[0]) == 0) return; // no file selected

    const file_path: []const u8 = std.mem.span(file_list.?[0]);

    _ = filter;
    _ = err;

    loaded = FS.init(file_path, allocator);
}
