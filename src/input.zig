const vaxis = @import("vaxis");

pub const Action = union(enum) {
    none,
    quit,
    redraw,
    start_command,
    move: struct {
        dx: i2,
        dy: i2,
    },
};

pub fn actionForKey(key: vaxis.Key) Action {
    if (key.matches('c', .{ .ctrl = true }) or key.matches('q', .{})) {
        return .quit;
    }
    if (key.matches('l', .{ .ctrl = true })) {
        return .redraw;
    }
    if (key.matches(':', .{}) or key.matches('/', .{})) {
        return .start_command;
    }
    if (key.matchesAny(&.{ 'h', 'a', vaxis.Key.left }, .{})) {
        return .{ .move = .{ .dx = -1, .dy = 0 } };
    }
    if (key.matchesAny(&.{ 'j', 's', vaxis.Key.down }, .{})) {
        return .{ .move = .{ .dx = 0, .dy = 1 } };
    }
    if (key.matchesAny(&.{ 'k', 'w', vaxis.Key.up }, .{})) {
        return .{ .move = .{ .dx = 0, .dy = -1 } };
    }
    if (key.matchesAny(&.{ 'l', 'd', vaxis.Key.right }, .{})) {
        return .{ .move = .{ .dx = 1, .dy = 0 } };
    }
    return .none;
}
