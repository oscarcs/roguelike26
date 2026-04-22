const std = @import("std");
const vaxis = @import("vaxis");
const game = @import("roguelike26");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer {
        const status = gpa.deinit();
        if (status == .leak) std.log.err("memory leak detected", .{});
    }
    const allocator = gpa.allocator();

    var tty_buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&tty_buffer);
    defer tty.deinit();

    var vx = try vaxis.init(allocator, .{});
    defer vx.deinit(allocator, tty.writer());

    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    var state = try game.Game.init(allocator);
    defer state.deinit();
    var ui_cache: game.view.Cache = .{};

    while (true) {
        switch (loop.nextEvent()) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) break;

                if (state.command_mode) {
                    if (try state.handleCommandKey(key) == .quit) break;
                } else {
                    const intent = game.input.actionForKey(key);
                    if (intent == .redraw) vx.queueRefresh();
                    if (try state.applyIntent(intent) == .quit) break;
                }
            },
            .winsize => |ws| try vx.resize(allocator, tty.writer(), ws),
            .focus_in => vx.queueRefresh(),
        }

        const presentation = ui_cache.present(&state);
        game.render.draw(vx.window(), presentation);
        try vx.render(tty.writer());
    }
}
