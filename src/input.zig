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
    if (key.matches('c', .{ .ctrl = true }) or key.matches('q', .{})) {
        return .quit;
    }
    if (key.matches('l', .{ .ctrl = true })) {
        return .redraw;
    }
    if (key.matches(':', .{}) or key.matches('/', .{})) {
        return .start_command;
    }
    if (key.matches('g', .{})) {
        return .pick_up;
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
