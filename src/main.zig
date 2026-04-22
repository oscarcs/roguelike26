const std = @import("std");
const vaxis = @import("vaxis");
const game = @import("roguelike26");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
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

    var state = game.Game.init(allocator);
    defer state.deinit();

    while (true) {
        switch (loop.nextEvent()) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) break;

                if (state.command_mode) {
                    try state.handleCommandKey(key);
                } else {
                    switch (game.input.actionForKey(key)) {
                        .quit => break,
                        .redraw => vx.queueRefresh(),
                        .start_command => state.beginCommandMode(),
                        .move => |delta| state.moveBy(delta.dx, delta.dy),
                        .none => {},
                    }
                }
            },
            .winsize => |ws| try vx.resize(allocator, tty.writer(), ws),
            .focus_in => vx.queueRefresh(),
        }

        game.render.draw(vx.window(), &state);
        try vx.render(tty.writer());
    }
}
