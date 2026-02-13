const sdl3 = @import("sdl3");
const std = @import("std");
const ent = @import("rom/ent.zig");
const graphics = @import("rom/graphics.zig");
const parsing = @import("rom/parsing.zig");
const FS = @import("rom/FS/FS.zig");
const events = @import("events.zig");

const FontSize = 14;

pub var eventQueue: std.PriorityQueue(events.UiEvent, void, sortEvent) = undefined;
pub var allocator: std.mem.Allocator = undefined;
pub var renderer: *sdl3.render.Renderer = undefined;
pub var font: sdl3.ttf.Font = undefined;
pub var textEngine: sdl3.ttf.RendererTextEngine = undefined;

var fps_capper: sdl3.extras.FramerateCapper(f32) = undefined;
pub var supress_inputs = false;
pub var mouse_clicked = false;
pub var mouse_scroll: f32 = 0;

fn get_font() !sdl3.ttf.Font {
    const env = std.process.getEnvMap(allocator) catch {
        @panic("env fail");
    };
    const wine_workaround = env.get("wine_workaround");
    if (wine_workaround != null) // because selfExeDirPathAlloc does not work in wine
        return try sdl3.ttf.Font.init("./zig-out/bin/JetBrainsMono-Regular.ttf", FontSize)
    else {
        const exe_dir = try std.fs.selfExeDirPathAlloc(allocator);
        const paths = [2][]const u8{ exe_dir, "JetBrainsMono-Regular.ttf" };
        const font_path = try std.fs.path.joinZ(allocator, &paths);
        return try sdl3.ttf.Font.init(font_path, FontSize);
    }
}

pub fn init(r: *sdl3.render.Renderer, a: std.mem.Allocator) !void {
    renderer = r;
    allocator = a;

    eventQueue = @TypeOf(eventQueue).init(a, undefined);
    fps_capper = sdl3.extras.FramerateCapper(f32){ .mode = .{ .limited = 30 } };

    textEngine = try sdl3.ttf.RendererTextEngine.init(renderer.*);
    font = try get_font();

    add_event(events.StartupEvent);
}

pub fn deinit() void {
    eventQueue.deinit();
    FS.deinit();
}

pub fn update() !bool {
    try renderer.clear();

    const quit = register_events();

    run_events();

    try renderer.present();

    return quit;
}

fn execute_event() !void {
    const event = eventQueue.remove();
    event.run(event.data);
}

pub fn add_event(event: events.UiEvent) void {
    eventQueue.add(event) catch unreachable;
}

fn register_events() bool {
    while (sdl3.events.poll()) |event|
        switch (event) {
            .quit => return true,
            .terminating => return true,
            .window_resized => add_event(events.WindowSizeChanged),
            .mouse_button_up => mouse_clicked = true,
            .mouse_wheel => mouse_scroll = event.mouse_wheel.scroll_y,
            else => {},
        };
    add_event(events.DrawPanelsEvent);
    add_event(events.TopPanelUpdateEvent);
    if (events.view_event) |event|
        add_event(event);
    if (events.display_event) |event|
        add_event(event);
    if (events.dropdown_event) |event|
        add_event(event);

    return false;
}

fn run_events() void {
    while (eventQueue.removeOrNull()) |event| {
        if (supress_inputs and event.type == .input) {
            continue;
        }
        event.run(event.data);
    }
    supress_inputs = false;
    mouse_clicked = false;
    mouse_scroll = 0;
}

fn sortEvent(_: void, a: events.UiEvent, b: events.UiEvent) std.math.Order {
    return std.math.order(@intFromEnum(a.prio), @intFromEnum(b.prio));
}

pub fn drawText(text: []const u8, x: f32, y: f32) !void {
    const rendtext = try renderText(text);
    try drawRenderedText(rendtext, x, y);
}

pub fn renderText(text: []const u8) !sdl3.ttf.Text {
    return try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&textEngine)).*, font, text);
}

pub fn drawRenderedText(text: sdl3.ttf.Text, x: f32, y: f32) !void {
    if (@intFromPtr(text.value) == 0) return; // it was occasionally segfaulting in wine without this
    try text.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(text, x, y);
}

const Corner = enum {
    topleft,
    topright,
    bottomleft,
    bottomright,
};

const Panel = struct {
    color: sdl3.pixels.Color,
    rect: sdl3.rect.Rect(f32),
    get_rect: *const fn () sdl3.rect.Rect(f32),

    pub fn relativeRect(self: *Panel, corner: Corner, x: f32, y: f32, w: f32, h: f32) sdl3.rect.Rect(f32) {
        return switch (corner) {
            .topleft => .{ .x = x + self.rect.x, .y = y + self.rect.y, .w = w, .h = h },
            .topright => .{ .x = -x + self.rect.x + self.rect.w, .y = y + self.rect.y, .w = w, .h = h },
            .bottomleft => .{ .x = x + self.rect.x, .y = -y + self.rect.y + self.rect.h, .w = w, .h = h },
            .bottomright => .{ .x = -x - self.rect.x + self.rect.w, .y = -y + self.rect.y + self.rect.h, .w = w, .h = h },
        };
    }

    pub fn relativePos(self: *Panel, corner: Corner, x: f32, y: f32) struct { f32, f32 } {
        const xpos = if (corner == .topleft or corner == .bottomleft) self.rect.x + x else self.rect.x + self.rect.w - x;
        const ypos = if (corner == .topleft or corner == .topright) self.rect.y + y else self.rect.y + self.rect.h - y;
        return .{ xpos, ypos };
    }

    pub fn relativeText(self: *Panel, text: []const u8, corner: Corner, x: f32, y: f32) !void {
        const pos = self.relativePos(corner, x, y);
        try drawText(text, pos.@"0", pos.@"1");
    }

    pub fn draw(self: *Panel) !void {
        try renderer.setDrawColor(self.color);
        try renderer.renderFillRect(self.rect);
    }
};

fn get_top_panel_rect() sdl3.rect.Rect(f32) {
    const size = renderer.getCurrentOutputSize() catch .{ 0, 0 };
    return .{ .x = 0, .y = 0, .w = @floatFromInt(size.@"0"), .h = 32 };
}
pub var top_panel: Panel = .{
    .color = rgb(48, 52, 70),
    .rect = undefined,
    .get_rect = &get_top_panel_rect,
};
fn get_main_panel_rect() sdl3.rect.Rect(f32) {
    const size = renderer.getCurrentOutputSize() catch .{ 0, 0 };
    return .{ .x = @floatFromInt(@divFloor(size.@"0", 5)), .y = 32, .w = @floatFromInt(size.@"0" - @divFloor(size.@"0", 5)), .h = @floatFromInt(size.@"1" - 32) };
}
pub var main_panel: Panel = .{
    .color = rgb(35, 38, 52),
    .rect = undefined,
    .get_rect = &get_main_panel_rect,
};
fn get_side_panel_rect() sdl3.rect.Rect(f32) {
    const size = renderer.getCurrentOutputSize() catch .{ 0, 0 };
    return .{ .x = 0, .y = 32, .w = @floatFromInt(@divFloor(size.@"0", 5)), .h = @floatFromInt(size.@"1" - 32) };
}
pub var side_panel: Panel = .{
    .color = rgb(41, 44, 60),
    .rect = undefined,
    .get_rect = &get_side_panel_rect,
};

pub fn rgb(r: comptime_int, g: comptime_int, b: comptime_int) sdl3.pixels.Color {
    return .{ .r = r, .g = g, .b = b, .a = 255 };
}

pub fn rgba(r: comptime_int, g: comptime_int, b: comptime_int, a: comptime_int) sdl3.pixels.Color {
    return .{ .r = r, .g = g, .b = b, .a = a };
}

pub fn NumInput(value: *usize, min: usize, max: usize, x: f32, y: f32) !f32 {
    const mouse = sdl3.mouse.getState();

    const minus = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&textEngine)).*, font, "-");
    try minus.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(minus, x, y);

    const charWidth: f32 = @floatFromInt((try minus.getSize()).@"0");
    const charHeight: f32 = @floatFromInt((try minus.getSize()).@"1");

    var buf: [20]u8 = undefined;
    const numString = try std.fmt.bufPrint(&buf, "{}/{}", .{ value.*, max });

    const rendtext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&textEngine)).*, font, numString);
    try rendtext.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(rendtext, x + charWidth, y);

    const plusX: f32 = x + charWidth + @as(f32, @floatFromInt((try rendtext.getSize()).@"0"));

    const plus = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&textEngine)).*, font, "+");
    try plus.setColor(198, 208, 245, 255);
    try sdl3.ttf.drawRendererText(plus, plusX, y);

    if (mouse_clicked) {
        if (mouse.@"1" > x and value.* > min and mouse.@"2" > y and mouse.@"1" < x + charWidth and mouse.@"2" < y + charHeight) {
            value.* -= 1;
        } else if (mouse.@"1" > plusX and value.* < max and mouse.@"2" > y and mouse.@"1" < plusX + charWidth and mouse.@"2" < y + charHeight) {
            value.* += 1;
        }
    }

    return plusX + @as(f32, @floatFromInt((try plus.getSize()).@"0")) - x;
}

pub fn Button(action: *const fn () anyerror!void, text: []const u8, x: f32, y: f32) !f32 {
    const cursor = sdl3.mouse.getState();

    const rendtext = try sdl3.ttf.Text.init(@as(*?sdl3.ttf.TextEngine, @ptrCast(&textEngine)).*, font, text);
    try rendtext.setColor(198, 208, 245, 255);

    const textsize = try rendtext.getSize();

    if (cursor.@"2" > y and cursor.@"1" > x and cursor.@"1" < x + @as(f32, @floatFromInt(textsize.@"0")) and cursor.@"2" < y + @as(f32, @floatFromInt(textsize.@"1"))) {
        try renderer.setDrawColor(rgb(65, 69, 89));
        try renderer.renderFillRect(.{
            .x = x,
            .y = y,
            .w = @as(f32, @floatFromInt(textsize.@"0")),
            .h = 24,
        });

        if (mouse_clicked) {
            try action();
        }
    } else {
        try renderer.setDrawColor(rgb(81, 87, 109));
        try renderer.renderFillRect(.{
            .x = x,
            .y = y,
            .w = @as(f32, @floatFromInt(textsize.@"0")),
            .h = 24,
        });
    }

    try sdl3.ttf.drawRendererText(rendtext, x, y);

    return @floatFromInt(textsize.@"0");
}
