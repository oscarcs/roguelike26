const std = @import("std");
const vaxis = @import("vaxis");
const content = @import("content.zig");
const input = @import("input.zig");
const world = @import("world.zig");

pub const max_hp: u16 = 30;
pub const max_stamina: u16 = 18;
pub const inventory_capacity = 12;
pub const local_map_radius_x: i32 = 26;
pub const local_map_radius_y: i32 = 15;
pub const minimap_span_x: i32 = 224;
pub const minimap_span_y: i32 = 144;

const log_capacity = 16;

const Message = struct {
    buf: [120]u8 = [_]u8{0} ** 120,
    len: usize = 0,
};

pub const Terrain = world.Terrain;
pub const Biome = world.Biome;
pub const Cover = world.Cover;
pub const Region = world.Region;
pub const Tile = world.Tile;
pub const Coord = world.Coord;
pub const ItemKind = content.ItemKind;
pub const FeatureKind = content.FeatureKind;

pub const Step = enum {
    running,
    quit,
};

pub const InventoryEntry = struct {
    kind: ItemKind,
    count: u8 = 1,
};

pub const FeatureState = struct {
    kind: FeatureKind,
    depleted: bool = false,
};

const WorldObjects = struct {
    allocator: std.mem.Allocator,
    ground_items: std.AutoHashMap(Coord, InventoryEntry),
    features: std.AutoHashMap(Coord, FeatureState),

    fn init(allocator: std.mem.Allocator) WorldObjects {
        return .{
            .allocator = allocator,
            .ground_items = std.AutoHashMap(Coord, InventoryEntry).init(allocator),
            .features = std.AutoHashMap(Coord, FeatureState).init(allocator),
        };
    }

    fn deinit(self: *WorldObjects) void {
        self.ground_items.deinit();
        self.features.deinit();
    }

    fn groundItemAt(self: *const WorldObjects, coord: Coord) ?InventoryEntry {
        return self.ground_items.get(coord);
    }

    fn featureAt(self: *const WorldObjects, coord: Coord) ?FeatureState {
        return self.features.get(coord);
    }

    fn featurePtr(self: *WorldObjects, coord: Coord) ?*FeatureState {
        return self.features.getPtr(coord);
    }

    fn putGroundItem(self: *WorldObjects, coord: Coord, item: InventoryEntry) !void {
        if (self.ground_items.getPtr(coord)) |existing| {
            if (existing.kind == item.kind and content.itemDef(item.kind).stackable) {
                existing.count +|= item.count;
                return;
            }
        }
        try self.ground_items.put(coord, item);
    }

    fn takeGroundItem(self: *WorldObjects, coord: Coord) ?InventoryEntry {
        if (self.ground_items.fetchRemove(coord)) |entry| {
            return entry.value;
        }
        return null;
    }

    fn putFeature(self: *WorldObjects, coord: Coord, feature: FeatureState) !void {
        try self.features.put(coord, feature);
    }
};

pub const Game = struct {
    allocator: std.mem.Allocator,
    world: world.World,
    objects: WorldObjects,
    player_x: i32 = 0,
    player_y: i32 = 0,
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
    inventory: [inventory_capacity]InventoryEntry = [_]InventoryEntry{.{ .kind = .iron_sword, .count = 0 }} ** inventory_capacity,
    inventory_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !Game {
        var self = Game{
            .allocator = allocator,
            .world = try world.World.init(allocator, world.randomSeed()),
            .objects = WorldObjects.init(allocator),
            .command_input = vaxis.widgets.TextInput.init(allocator),
        };
        errdefer self.world.deinit();
        errdefer self.objects.deinit();
        errdefer self.command_input.deinit();

        self.player_x = self.world.spawn.x;
        self.player_y = self.world.spawn.y;

        try self.seedStartingInventory();
        try self.seedWorldObjects();

        self.pushMessage("The expedition enters the overworld at first light.", .{});
        self.pushMessage("Move with hjkl, WASD, or the arrow keys.", .{});
        self.pushMessage("Press g to pick up, e to interact, or : for commands.", .{});
        return self;
    }

    pub fn deinit(self: *Game) void {
        self.command_input.deinit();
        self.objects.deinit();
        self.world.deinit();
    }

    pub fn beginCommandMode(self: *Game) void {
        self.command_mode = true;
        self.command_input.clearRetainingCapacity();
    }

    pub fn cancelCommandMode(self: *Game) void {
        self.command_mode = false;
        self.command_input.clearRetainingCapacity();
    }

    pub fn handleCommandKey(self: *Game, key: vaxis.Key) !Step {
        if (key.matches(vaxis.Key.escape, .{})) {
            self.cancelCommandMode();
            return .running;
        }
        if (key.matches(vaxis.Key.enter, .{})) {
            return self.submitCommand();
        }
        try self.command_input.update(.{ .key_press = key });
        return .running;
    }

    pub fn applyIntent(self: *Game, intent: input.Intent) !Step {
        switch (intent) {
            .none, .redraw => return .running,
            .quit => return .quit,
            .start_command => {
                self.beginCommandMode();
                return .running;
            },
            .move => |delta| {
                self.moveBy(delta.dx, delta.dy);
                return .running;
            },
            .help => {
                self.pushMessage("Commands: help, look, rest, where, inventory, clear, pickup, interact, use <slot>.", .{});
                return .running;
            },
            .look => {
                self.describeCurrentLocation();
                return .running;
            },
            .rest => {
                self.restHere();
                return .running;
            },
            .where => {
                self.pushMessage("Grid {d},{d} in {s}.", .{
                    self.player_x,
                    self.player_y,
                    regionName(self.currentRegion()),
                });
                return .running;
            },
            .inventory => {
                self.describeInventory();
                return .running;
            },
            .clear_log => {
                self.clearMessages();
                self.pushMessage("The log has been cleared.", .{});
                return .running;
            },
            .pick_up => {
                self.pickUpAtCurrentTile();
                return .running;
            },
            .interact => {
                self.interactAtCurrentTile();
                return .running;
            },
            .use_item_slot => |slot| {
                self.useInventorySlot(slot);
                return .running;
            },
            .use_item_name => |name| {
                self.useInventoryNamed(name);
                return .running;
            },
        }
    }

    pub fn terrainAt(self: *Game, x: i32, y: i32) Terrain {
        return self.world.terrainAt(x, y);
    }

    pub fn tileAt(self: *Game, x: i32, y: i32) Tile {
        return self.world.tileAt(x, y);
    }

    pub fn biomeAt(self: *Game, x: i32, y: i32) Biome {
        return self.world.biomeAt(x, y);
    }

    pub fn currentTerrain(self: *Game) Terrain {
        return self.terrainAt(self.player_x, self.player_y);
    }

    pub fn currentBiome(self: *Game) Biome {
        return self.biomeAt(self.player_x, self.player_y);
    }

    pub fn currentCover(self: *Game) Cover {
        return self.tileAt(self.player_x, self.player_y).cover;
    }

    pub fn currentRegion(self: *Game) Region {
        return self.world.regionAt(self.player_x, self.player_y);
    }

    pub fn regionAt(self: *Game, x: i32, y: i32) Region {
        return self.world.regionAt(x, y);
    }

    pub fn logCount(self: *const Game) usize {
        return self.message_len;
    }

    pub fn logMessage(self: *const Game, index: usize) []const u8 {
        const start = if (self.message_len == log_capacity) self.message_next else 0;
        const slot = (start + index) % log_capacity;
        return self.messages[slot].buf[0..self.messages[slot].len];
    }

    pub fn currentLandmark(self: *Game) []const u8 {
        return world.regionInfo(self.currentRegion()).landmark;
    }

    pub fn regionSummary(self: *Game) []const u8 {
        return world.regionInfo(self.currentRegion()).summary;
    }

    pub fn objectiveCoord(self: *const Game) Coord {
        return self.world.objective;
    }

    pub fn inventoryCount(self: *const Game) usize {
        return self.inventory_len;
    }

    pub fn inventoryItem(self: *const Game, index: usize) InventoryEntry {
        return self.inventory[index];
    }

    pub fn currentCoord(self: *const Game) Coord {
        return .{ .x = self.player_x, .y = self.player_y };
    }

    pub fn featureAt(self: *const Game, x: i32, y: i32) ?FeatureState {
        return self.objects.featureAt(.{ .x = x, .y = y });
    }

    pub fn groundItemAt(self: *const Game, x: i32, y: i32) ?InventoryEntry {
        return self.objects.groundItemAt(.{ .x = x, .y = y });
    }

    fn submitCommand(self: *Game) !Step {
        const raw = try self.command_input.toOwnedSlice();
        defer self.allocator.free(raw);
        defer self.command_mode = false;

        const trimmed = std.mem.trim(u8, raw, " \t");
        if (trimmed.len == 0) {
            self.pushMessage("You hold position and say nothing.", .{});
            return .running;
        }

        self.pushMessage("> {s}", .{trimmed});

        return switch (input.actionForCommand(trimmed)) {
            .empty => .running,
            .unknown => blk: {
                self.pushMessage("Unknown command. Try help, pickup, interact, or use <slot>.", .{});
                break :blk .running;
            },
            .action => |action| self.applyIntent(action),
        };
    }

    fn seedStartingInventory(self: *Game) !void {
        try self.addInventoryItem(.{ .kind = .iron_sword, .count = 1 });
        try self.addInventoryItem(.{ .kind = .weather_cloak, .count = 1 });
        try self.addInventoryItem(.{ .kind = .flint_and_steel, .count = 1 });
        try self.addInventoryItem(.{ .kind = .bandage_roll, .count = 1 });
        try self.addInventoryItem(.{ .kind = .old_map_fragment, .count = 1 });
        try self.addInventoryItem(.{ .kind = .amber_vial, .count = 1 });
    }

    fn seedWorldObjects(self: *Game) !void {
        const spawn = self.currentCoord();
        try self.objects.putFeature(spawn, .{ .kind = .campfire });

        const cache_coord = self.findNearbyTerrain(spawn, 10, .ruins) orelse
            self.findNearbyTerrain(spawn, 10, .plains) orelse
            self.findNearbyWalkable(spawn, 10) orelse spawn;
        if (!std.meta.eql(cache_coord, spawn) or self.objects.featureAt(cache_coord) == null) {
            try self.objects.putFeature(cache_coord, .{ .kind = .supply_cache });
        }

        const bush_coord = self.findNearbyTerrain(spawn, 12, .forest) orelse
            self.findNearbyTerrain(spawn, 12, .plains) orelse
            self.findNearbyWalkable(spawn, 12) orelse spawn;
        if (self.objects.featureAt(bush_coord) == null) {
            try self.objects.putFeature(bush_coord, .{ .kind = .berry_bush });
        }

        const waypoint = self.findNearbyWalkable(self.world.objective, 6) orelse self.world.objective;
        if (self.objects.featureAt(waypoint) == null) {
            try self.objects.putFeature(waypoint, .{ .kind = .waystone });
        }

        const ration_coord = self.findNearbyTerrain(spawn, 8, .hills) orelse
            self.findNearbyWalkable(spawn, 8) orelse spawn;
        if (self.objects.groundItemAt(ration_coord) == null) {
            try self.objects.putGroundItem(ration_coord, .{ .kind = .trail_rations, .count = 1 });
        }

        const salve_coord = self.findNearbyTerrain(spawn, 10, .marsh) orelse bush_coord;
        if (self.objects.groundItemAt(salve_coord) == null) {
            try self.objects.putGroundItem(salve_coord, .{ .kind = .marsh_salve, .count = 1 });
        }
    }

    fn moveBy(self: *Game, dx: i2, dy: i2) void {
        const next_x = offsetAxis(self.player_x, dx);
        const next_y = offsetAxis(self.player_y, dy);

        const terrain = self.terrainAt(next_x, next_y);
        if (!terrainWalkable(terrain)) {
            self.pushMessage("The {s} turn you back.", .{terrainName(terrain)});
            return;
        }

        self.player_x = next_x;
        self.player_y = next_y;
        self.spendTurn(movementCost(terrain));
        self.announceArrival();
    }

    fn restHere(self: *Game) void {
        self.spendTurn(0);
        self.hp = @min(max_hp, self.hp + 2);
        self.stamina = @min(max_stamina, self.stamina + 4);
        self.pushMessage("Turn {d}: you rest and recover your breath.", .{self.turn});
    }

    fn describeCurrentLocation(self: *Game) void {
        self.pushMessage("You study the {s} in {s}.", .{
            terrainName(self.currentTerrain()),
            regionName(self.currentRegion()),
        });
        self.pushMessage("The ground here is {s} over {s}.", .{
            coverName(self.currentCover()),
            biomeName(self.currentBiome()),
        });

        if (self.objects.featureAt(self.currentCoord())) |feature| {
            const def = content.featureDef(feature.kind);
            if (feature.depleted and def.single_use) {
                self.pushMessage("The {s} has already been picked clean.", .{def.name});
            } else {
                self.pushMessage("{s}: {s}", .{ def.name, def.description });
            }
        }

        if (self.objects.groundItemAt(self.currentCoord())) |item| {
            const def = content.itemDef(item.kind);
            self.pushMessage("On the ground: {s}.", .{def.name});
        }
    }

    fn describeInventory(self: *Game) void {
        if (self.inventory_len == 0) {
            self.pushMessage("Your pack is empty.", .{});
            return;
        }

        self.pushMessage("You carry {d} inventory entries. Use 'use <slot>' for consumables.", .{
            self.inventory_len,
        });
    }

    fn pickUpAtCurrentTile(self: *Game) void {
        const coord = self.currentCoord();
        const item = self.objects.takeGroundItem(coord) orelse {
            self.pushMessage("There is nothing here to pick up.", .{});
            return;
        };

        self.addInventoryItem(item) catch {
            self.pushMessage("Your pack is full, so you leave the {s} where it lies.", .{
                content.itemDef(item.kind).name,
            });
            self.objects.putGroundItem(coord, item) catch {};
            return;
        };

        self.spendTurn(0);
        if (item.count > 1) {
            self.pushMessage("You pack away {d}x {s}.", .{ item.count, content.itemDef(item.kind).name });
        } else {
            self.pushMessage("You pick up the {s}.", .{content.itemDef(item.kind).name});
        }
    }

    fn interactAtCurrentTile(self: *Game) void {
        const coord = self.currentCoord();
        const feature = self.objects.featurePtr(coord) orelse {
            self.pushMessage("There is nothing here that answers your attention.", .{});
            return;
        };
        const def = content.featureDef(feature.kind);

        if (feature.depleted and def.single_use) {
            self.pushMessage("The {s} has nothing left to offer.", .{def.name});
            return;
        }

        switch (feature.kind) {
            .campfire => {
                self.spendTurn(0);
                self.hp = @min(max_hp, self.hp + 3);
                self.stamina = @min(max_stamina, self.stamina + 5);
                self.pushMessage("You warm yourself at the campfire and steady your nerves.", .{});
            },
            .berry_bush => {
                self.addInventoryItem(.{ .kind = .trail_rations, .count = 1 }) catch {
                    self.pushMessage("Your pack is too full to gather anything from the bush.", .{});
                    return;
                };
                feature.depleted = true;
                self.spendTurn(0);
                self.pushMessage("You forage the bush and tuck away a fresh ration.", .{});
            },
            .supply_cache => {
                var added_bandage = false;
                var added_vial = false;
                if (self.addInventoryItem(.{ .kind = .bandage_roll, .count = 1 })) |_| {
                    added_bandage = true;
                } else |_| {}
                if (self.addInventoryItem(.{ .kind = .amber_vial, .count = 1 })) |_| {
                    added_vial = true;
                } else |_| {}

                if (!added_bandage and !added_vial) {
                    self.pushMessage("The cache is intact, but your pack has no room for it.", .{});
                    return;
                }

                feature.depleted = true;
                self.spendTurn(0);
                if (added_bandage and added_vial) {
                    self.pushMessage("The cache yields a bandage roll and an amber vial.", .{});
                } else if (added_bandage) {
                    self.pushMessage("The cache yields a bandage roll before the rest has to stay behind.", .{});
                } else {
                    self.pushMessage("The cache yields an amber vial before the rest has to stay behind.", .{});
                }
            },
            .waystone => {
                self.spendTurn(0);
                self.pushMessage("The waystone's grooves still point toward the Watcher's Spire at {d},{d}.", .{
                    self.world.objective.x,
                    self.world.objective.y,
                });
            },
        }
    }

    fn useInventorySlot(self: *Game, slot: usize) void {
        if (slot >= self.inventory_len) {
            self.pushMessage("No inventory entry matches slot {d}.", .{slot + 1});
            return;
        }

        const entry = self.inventory[slot];
        const def = content.itemDef(entry.kind);
        switch (def.effect) {
            .none => self.pushMessage("The {s} has no direct use right now.", .{def.name}),
            .restore => |restore| {
                self.spendTurn(0);
                self.hp = @min(max_hp, self.hp + restore.hp);
                self.stamina = @min(max_stamina, self.stamina + restore.stamina);
                if (def.consumed_on_use) self.consumeInventorySlot(slot, 1);
                self.pushMessage("You use the {s}.", .{def.name});
            },
        }
    }

    fn useInventoryNamed(self: *Game, name: []const u8) void {
        const slot = self.findInventoryByName(name) orelse {
            self.pushMessage("You are not carrying '{s}'.", .{name});
            return;
        };
        self.useInventorySlot(slot);
    }

    fn addInventoryItem(self: *Game, item: InventoryEntry) !void {
        const def = content.itemDef(item.kind);
        if (def.stackable) {
            var i: usize = 0;
            while (i < self.inventory_len) : (i += 1) {
                if (self.inventory[i].kind == item.kind) {
                    self.inventory[i].count +|= item.count;
                    return;
                }
            }
        }

        if (self.inventory_len >= inventory_capacity) {
            return error.InventoryFull;
        }

        self.inventory[self.inventory_len] = item;
        self.inventory_len += 1;
    }

    fn consumeInventorySlot(self: *Game, slot: usize, amount: u8) void {
        if (self.inventory[slot].count > amount) {
            self.inventory[slot].count -= amount;
            return;
        }

        var i = slot;
        while (i + 1 < self.inventory_len) : (i += 1) {
            self.inventory[i] = self.inventory[i + 1];
        }
        self.inventory_len -= 1;
    }

    fn findInventoryByName(self: *const Game, name: []const u8) ?usize {
        var i: usize = 0;
        while (i < self.inventory_len) : (i += 1) {
            if (std.ascii.eqlIgnoreCase(content.itemDef(self.inventory[i].kind).name, name)) {
                return i;
            }
        }
        return null;
    }

    fn spendTurn(self: *Game, stamina_cost: u16) void {
        self.turn += 1;
        self.stamina = self.stamina -| stamina_cost;
        if (self.turn % 5 == 0 and self.stamina < max_stamina) {
            self.stamina += 1;
        }
    }

    fn announceArrival(self: *Game) void {
        if (self.objects.featureAt(self.currentCoord())) |feature| {
            const def = content.featureDef(feature.kind);
            if (feature.depleted and def.single_use) {
                self.pushMessage("You return to the spent {s}.", .{def.name});
            } else {
                self.pushMessage("You arrive at a {s}. {s}", .{ def.name, def.interaction_hint });
            }
        }
        if (self.objects.groundItemAt(self.currentCoord())) |item| {
            self.pushMessage("Something lies here: {s}.", .{content.itemDef(item.kind).name});
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

    fn findNearbyTerrain(self: *Game, origin: Coord, radius: i32, terrain: Terrain) ?Coord {
        var y = origin.y - radius;
        while (y <= origin.y + radius) : (y += 1) {
            var x = origin.x - radius;
            while (x <= origin.x + radius) : (x += 1) {
                const coord = Coord{ .x = x, .y = y };
                if (std.meta.eql(coord, origin)) continue;
                if (self.terrainAt(coord.x, coord.y) != terrain) continue;
                if (!terrainWalkable(self.terrainAt(coord.x, coord.y))) continue;
                if (self.objects.featureAt(coord) != null) continue;
                return coord;
            }
        }
        return null;
    }

    fn findNearbyWalkable(self: *Game, origin: Coord, radius: i32) ?Coord {
        var y = origin.y - radius;
        while (y <= origin.y + radius) : (y += 1) {
            var x = origin.x - radius;
            while (x <= origin.x + radius) : (x += 1) {
                const coord = Coord{ .x = x, .y = y };
                if (!terrainWalkable(self.terrainAt(coord.x, coord.y))) continue;
                if (self.objects.featureAt(coord) != null) continue;
                return coord;
            }
        }
        return null;
    }
};

pub fn terrainName(terrain: Terrain) []const u8 {
    return world.terrainName(terrain);
}

pub fn regionName(region: Region) []const u8 {
    return world.regionInfo(region).name;
}

pub fn biomeName(biome: Biome) []const u8 {
    return world.biomeName(biome);
}

pub fn coverName(cover: Cover) []const u8 {
    return world.coverName(cover);
}

pub fn terrainWalkable(terrain: Terrain) bool {
    return world.terrainWalkable(terrain);
}

pub fn itemDefinition(kind: ItemKind) content.ItemDef {
    return content.itemDef(kind);
}

pub fn featureDefinition(kind: FeatureKind) content.FeatureDef {
    return content.featureDef(kind);
}

fn movementCost(terrain: Terrain) u16 {
    return world.movementCost(terrain);
}

fn offsetAxis(value: i32, delta: i2) i32 {
    return switch (delta) {
        -1 => value - 1,
        0 => value,
        1 => value + 1,
        else => value,
    };
}
