const std = @import("std");
const vaxis = @import("vaxis");

pub const Intent = union(enum) {
    none,
    quit,
    redraw,
    start_command,
    move: struct {
        dx: i2,
        dy: i2,
    },
    help,
    look,
    rest,
    where,
    inventory,
    clear_log,
    pick_up,
    interact,
    use_item_slot: usize,
    use_item_name: []const u8,
};

pub const ParsedCommand = union(enum) {
    empty,
    action: Intent,
    unknown,
};

pub fn actionForKey(key: vaxis.Key) Intent {
    if (key.matches('c', .{ .ctrl = true })) {
        return .quit;
    }
    if (key.matches('l', .{ .ctrl = true })) {
        return .redraw;
    }
    if (key.matches(':', .{}) or key.matches('/', .{})) {
        return .start_command;
    }
    if (key.matches('g', .{}) or key.matches('q', .{})) {
        return .pick_up;
    }
    if (numberSlotForKey(key)) |slot| {
        return .{ .use_item_slot = slot };
    }
    if (key.matches('e', .{})) {
        return .interact;
    }
    if (key.matches('r', .{})) {
        return .rest;
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

fn numberSlotForKey(key: vaxis.Key) ?usize {
    if (key.matches('1', .{})) return 0;
    if (key.matches('2', .{})) return 1;
    if (key.matches('3', .{})) return 2;
    if (key.matches('4', .{})) return 3;
    if (key.matches('5', .{})) return 4;
    if (key.matches('6', .{})) return 5;
    if (key.matches('7', .{})) return 6;
    if (key.matches('8', .{})) return 7;
    if (key.matches('9', .{})) return 8;
    if (key.matches('0', .{})) return 9;
    return null;
}

pub fn actionForCommand(command: []const u8) ParsedCommand {
    const trimmed = std.mem.trim(u8, command, " \t");
    if (trimmed.len == 0) return .empty;

    if (std.ascii.eqlIgnoreCase(trimmed, "help")) return .{ .action = .help };
    if (std.ascii.eqlIgnoreCase(trimmed, "look")) return .{ .action = .look };
    if (std.ascii.eqlIgnoreCase(trimmed, "rest")) return .{ .action = .rest };
    if (std.ascii.eqlIgnoreCase(trimmed, "where")) return .{ .action = .where };
    if (std.ascii.eqlIgnoreCase(trimmed, "inventory")) return .{ .action = .inventory };
    if (std.ascii.eqlIgnoreCase(trimmed, "clear")) return .{ .action = .clear_log };
    if (std.ascii.eqlIgnoreCase(trimmed, "pickup") or std.ascii.eqlIgnoreCase(trimmed, "pick up")) {
        return .{ .action = .pick_up };
    }
    if (std.ascii.eqlIgnoreCase(trimmed, "interact") or std.ascii.eqlIgnoreCase(trimmed, "use world")) {
        return .{ .action = .interact };
    }
    if (std.ascii.eqlIgnoreCase(trimmed, "quit")) return .{ .action = .quit };

    if (startsWithIgnoreCase(trimmed, "use ")) {
        const target = std.mem.trim(u8, trimmed[4..], " \t");
        if (target.len == 0) return .unknown;
        if (std.fmt.parseInt(usize, target, 10)) |slot| {
            if (slot == 0) return .unknown;
            return .{ .action = .{ .use_item_slot = slot - 1 } };
        } else |_| {
            return .{ .action = .{ .use_item_name = target } };
        }
    }

    return .unknown;
}

fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool {
    if (haystack.len < prefix.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[0..prefix.len], prefix);
}

test "q is a pickup shortcut, not quit" {
    try std.testing.expectEqual(Intent.pick_up, actionForKey(.{ .codepoint = 'q' }));
}

test "number keys use inventory slots" {
    try std.testing.expectEqual(@as(usize, 0), actionForKey(.{ .codepoint = '1' }).use_item_slot);
    try std.testing.expectEqual(@as(usize, 4), actionForKey(.{ .codepoint = '5' }).use_item_slot);
    try std.testing.expectEqual(@as(usize, 9), actionForKey(.{ .codepoint = '0' }).use_item_slot);
}
