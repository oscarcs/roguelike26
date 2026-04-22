const std = @import("std");
const vaxis = @import("vaxis");

pub const world_width: u16 = 96;
pub const world_height: u16 = 64;
pub const max_hp: u16 = 30;
pub const max_stamina: u16 = 18;

pub const inventory_items = [_][]const u8{
    "Iron sword",
    "Weather cloak",
    "Flint and steel",
    "Bandage roll",
    "Old map fragment",
    "Amber vial",
};

const log_capacity = 16;
const Message = struct {
    buf: [120]u8 = [_]u8{0} ** 120,
    len: usize = 0,
};

pub const Terrain = enum {
    plains,
    forest,
    hills,
    marsh,
    ruins,
    water,
};

pub const Region = enum {
    ember_fields,
    mistwood,
    glass_marsh,
    iron_ridge,
    dusk_road,
};

pub const Game = struct {
    allocator: std.mem.Allocator,
    player_x: u16 = world_width / 2,
    player_y: u16 = world_height / 2,
    turn: u32 = 1,
    hp: u16 = 24,
    stamina: u16 = 14,
    level: u8 = 2,
    gold: u16 = 37,
    command_mode: bool = false,
    command_input: vaxis.widgets.TextInput,
    messages: [log_capacity]Message = [_]Message{.{}} ** log_capacity,
    message_next: usize = 0,
    message_len: usize = 0,
    hp_text_buf: [12]u8 = undefined,
    hp_text_len: usize = 0,
    stamina_text_buf: [12]u8 = undefined,
    stamina_text_len: usize = 0,
    level_text_buf: [8]u8 = undefined,
    level_text_len: usize = 0,
    gold_text_buf: [8]u8 = undefined,
    gold_text_len: usize = 0,
    turn_text_buf: [12]u8 = undefined,
    turn_text_len: usize = 0,
    coords_text_buf: [16]u8 = undefined,
    coords_text_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator) Game {
        var self = Game{
            .allocator = allocator,
            .command_input = vaxis.widgets.TextInput.init(allocator),
        };

        if (!terrainWalkable(self.terrainAt(self.player_x, self.player_y))) {
            self.player_x = 8;
            self.player_y = 8;
        }

        self.refreshHudText();
        self.pushMessage("The expedition enters the overworld at first light.", .{});
        self.pushMessage("Move with hjkl, WASD, or the arrow keys.", .{});
        self.pushMessage("Press : or / to enter a command.", .{});
        return self;
    }

    pub fn deinit(self: *Game) void {
        self.command_input.deinit();
    }

    pub fn beginCommandMode(self: *Game) void {
        self.command_mode = true;
        self.command_input.clearRetainingCapacity();
    }

    pub fn cancelCommandMode(self: *Game) void {
        self.command_mode = false;
        self.command_input.clearRetainingCapacity();
    }

    pub fn handleCommandKey(self: *Game, key: vaxis.Key) !void {
        if (key.matches(vaxis.Key.escape, .{})) {
            self.cancelCommandMode();
            return;
        }
        if (key.matches(vaxis.Key.enter, .{})) {
            try self.submitCommand();
            return;
        }
        try self.command_input.update(.{ .key_press = key });
    }

    pub fn moveBy(self: *Game, dx: i2, dy: i2) void {
        const next_x = clampAxis(self.player_x, dx, world_width);
        const next_y = clampAxis(self.player_y, dy, world_height);

        if (next_x == self.player_x and next_y == self.player_y) {
            self.pushMessage("The edge of the known world stops you.", .{});
            return;
        }

        const terrain = self.terrainAt(next_x, next_y);
        if (!terrainWalkable(terrain)) {
            self.pushMessage("The {s} turn you back.", .{terrainName(terrain)});
            return;
        }

        self.player_x = next_x;
        self.player_y = next_y;
        self.turn += 1;

        const cost = movementCost(terrain);
        self.stamina = self.stamina -| cost;
        if (self.turn % 5 == 0 and self.stamina < max_stamina) {
            self.stamina += 1;
        }

        self.refreshHudText();
        self.pushMessage("Turn {d}: you cross into {s}.", .{
            self.turn,
            terrainName(terrain),
        });
    }

    pub fn terrainAt(self: *const Game, x: u16, y: u16) Terrain {
        _ = self;
        return terrainForCoord(x, y);
    }

    pub fn currentTerrain(self: *const Game) Terrain {
        return self.terrainAt(self.player_x, self.player_y);
    }

    pub fn currentRegion(self: *const Game) Region {
        return regionForCoord(self.player_x, self.player_y);
    }

    pub fn regionAt(self: *const Game, x: u16, y: u16) Region {
        _ = self;
        return regionForCoord(x, y);
    }

    pub fn logCount(self: *const Game) usize {
        return self.message_len;
    }

    pub fn logMessage(self: *const Game, index: usize) []const u8 {
        const start = if (self.message_len == log_capacity) self.message_next else 0;
        const slot = (start + index) % log_capacity;
        return self.messages[slot].buf[0..self.messages[slot].len];
    }

    pub fn currentLandmark(self: *const Game) []const u8 {
        return switch (self.currentRegion()) {
            .ember_fields => "Sunwheel stones on the western rise",
            .mistwood => "A watchfire hidden beneath the pines",
            .glass_marsh => "The broken ferry half-swallowed by reeds",
            .iron_ridge => "A signal tower above the shale path",
            .dusk_road => "The Watcher's Spire on the horizon",
        };
    }

    pub fn regionSummary(self: *const Game) []const u8 {
        return switch (self.currentRegion()) {
            .ember_fields => "Open grasslands with long sightlines and scattered ruins.",
            .mistwood => "Dense tree cover muffles sound and hides narrow trails.",
            .glass_marsh => "Wet ground slows travel while drowned paths split and rejoin.",
            .iron_ridge => "Hard ridges and switchbacks reward careful route planning.",
            .dusk_road => "Ancient stonework hints at a safer passage east.",
        };
    }

    pub fn objective(self: *const Game) []const u8 {
        _ = self;
        return "Reach the Watcher's Spire and chart a safe approach.";
    }

    pub fn commandHint(self: *const Game) []const u8 {
        if (self.command_mode) return "Enter submits. Esc cancels.";
        return "Press : or / to focus the command line.";
    }

    pub fn hpText(self: *const Game) []const u8 {
        return self.hp_text_buf[0..self.hp_text_len];
    }

    pub fn staminaText(self: *const Game) []const u8 {
        return self.stamina_text_buf[0..self.stamina_text_len];
    }

    pub fn levelText(self: *const Game) []const u8 {
        return self.level_text_buf[0..self.level_text_len];
    }

    pub fn goldText(self: *const Game) []const u8 {
        return self.gold_text_buf[0..self.gold_text_len];
    }

    pub fn turnText(self: *const Game) []const u8 {
        return self.turn_text_buf[0..self.turn_text_len];
    }

    pub fn coordsText(self: *const Game) []const u8 {
        return self.coords_text_buf[0..self.coords_text_len];
    }

    fn submitCommand(self: *Game) !void {
        const raw = try self.command_input.toOwnedSlice();
        defer self.allocator.free(raw);
        defer self.command_mode = false;

        const trimmed = std.mem.trim(u8, raw, " \t");
        if (trimmed.len == 0) {
            self.pushMessage("You hold position and say nothing.", .{});
            return;
        }

        self.pushMessage("> {s}", .{trimmed});

        if (std.ascii.eqlIgnoreCase(trimmed, "help")) {
            self.pushMessage("Commands: help, look, rest, where, inventory, clear.", .{});
        } else if (std.ascii.eqlIgnoreCase(trimmed, "look")) {
            self.pushMessage("You study the {s}. {s}", .{
                terrainName(self.currentTerrain()),
                self.regionSummary(),
            });
        } else if (std.ascii.eqlIgnoreCase(trimmed, "rest")) {
            self.turn += 1;
            self.stamina = @min(max_stamina, self.stamina + 4);
            self.hp = @min(max_hp, self.hp + 2);
            self.refreshHudText();
            self.pushMessage("Turn {d}: you rest and recover your breath.", .{self.turn});
        } else if (std.ascii.eqlIgnoreCase(trimmed, "where")) {
            self.pushMessage("Grid {d},{d} in {s}.", .{
                self.player_x,
                self.player_y,
                regionName(self.currentRegion()),
            });
        } else if (std.ascii.eqlIgnoreCase(trimmed, "inventory")) {
            self.pushMessage("Pack check: {s}, {s}, and {s}.", .{
                inventory_items[0],
                inventory_items[3],
                inventory_items[4],
            });
        } else if (std.ascii.eqlIgnoreCase(trimmed, "clear")) {
            self.clearMessages();
            self.pushMessage("The log has been cleared.", .{});
        } else {
            self.pushMessage("Unknown command. Type help for a short list.", .{});
        }
    }

    fn clearMessages(self: *Game) void {
        self.messages = [_]Message{.{}} ** log_capacity;
        self.message_next = 0;
        self.message_len = 0;
    }

    fn pushMessage(self: *Game, comptime fmt: []const u8, args: anytype) void {
        const slot = self.message_next;
        const text = std.fmt.bufPrint(&self.messages[slot].buf, fmt, args) catch unreachable;
        self.messages[slot].len = text.len;
        self.message_next = (self.message_next + 1) % log_capacity;
        if (self.message_len < log_capacity) self.message_len += 1;
    }

    fn refreshHudText(self: *Game) void {
        self.hp_text_len = (std.fmt.bufPrint(&self.hp_text_buf, "{d}/{d}", .{
            self.hp,
            max_hp,
        }) catch unreachable).len;
        self.stamina_text_len = (std.fmt.bufPrint(&self.stamina_text_buf, "{d}/{d}", .{
            self.stamina,
            max_stamina,
        }) catch unreachable).len;
        self.level_text_len = (std.fmt.bufPrint(&self.level_text_buf, "{d}", .{
            self.level,
        }) catch unreachable).len;
        self.gold_text_len = (std.fmt.bufPrint(&self.gold_text_buf, "{d}", .{
            self.gold,
        }) catch unreachable).len;
        self.turn_text_len = (std.fmt.bufPrint(&self.turn_text_buf, "{d}", .{
            self.turn,
        }) catch unreachable).len;
        self.coords_text_len = (std.fmt.bufPrint(&self.coords_text_buf, "{d},{d}", .{
            self.player_x,
            self.player_y,
        }) catch unreachable).len;
    }
};

pub fn terrainName(terrain: Terrain) []const u8 {
    return switch (terrain) {
        .plains => "open plains",
        .forest => "mistwood",
        .hills => "iron hills",
        .marsh => "glass marsh",
        .ruins => "fallen ruins",
        .water => "deep water",
    };
}

pub fn regionName(region: Region) []const u8 {
    return switch (region) {
        .ember_fields => "Ember Fields",
        .mistwood => "Mistwood",
        .glass_marsh => "Glass Marsh",
        .iron_ridge => "Iron Ridge",
        .dusk_road => "Dusk Road",
    };
}

pub fn terrainWalkable(terrain: Terrain) bool {
    return terrain != .water;
}

fn terrainForCoord(x: u16, y: u16) Terrain {
    const region = regionForCoord(x, y);
    const sample = hash2d(x / 2, y / 2) % 100;

    return switch (region) {
        .ember_fields => if (sample < 8) .ruins else if (sample < 18) .hills else .plains,
        .mistwood => if (sample < 10) .water else if (sample < 72) .forest else .plains,
        .glass_marsh => if (sample < 26) .water else if (sample < 82) .marsh else .plains,
        .iron_ridge => if (sample < 18) .forest else if (sample < 80) .hills else .ruins,
        .dusk_road => if (sample < 12) .water else if (sample < 34) .ruins else if (sample < 58) .hills else .plains,
    };
}

fn regionForCoord(x: u16, y: u16) Region {
    const band_x = x * 5 / world_width;
    const band_y = y * 4 / world_height;
    const selector = (band_x + band_y * 2 + hash2d(x / 12, y / 10)) % 5;

    return switch (selector) {
        0 => .ember_fields,
        1 => .mistwood,
        2 => .glass_marsh,
        3 => .iron_ridge,
        else => .dusk_road,
    };
}

fn movementCost(terrain: Terrain) u16 {
    return switch (terrain) {
        .marsh, .hills => 2,
        else => 1,
    };
}

fn hash2d(x: u16, y: u16) u16 {
    var value: u32 = @as(u32, x);
    value *%= 0x045d9f3b;

    var y_mix: u32 = @as(u32, y);
    y_mix *%= 0x119de1f3;
    value +%= y_mix;

    value ^= value >> 16;
    value *%= 0x45d9f3b;
    value ^= value >> 15;
    return @intCast(value & 0xffff);
}

fn clampAxis(value: u16, delta: i2, max_exclusive: u16) u16 {
    const max_index = max_exclusive - 1;

    return switch (delta) {
        -1 => if (value == 0) 0 else value - 1,
        0 => value,
        1 => if (value >= max_index) max_index else value + 1,
        else => value,
    };
}
