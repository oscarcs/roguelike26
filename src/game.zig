const std = @import("std");
const vaxis = @import("vaxis");
const content = @import("content.zig");
const encounters = @import("encounters.zig");
const generation = @import("generation.zig");
const input = @import("input.zig");
const objects = @import("objects.zig");
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
pub const InventoryEntry = objects.InventoryEntry;
pub const FeatureState = objects.FeatureState;
pub const EncounterKind = encounters.Kind;
pub const Encounter = encounters.Encounter;

pub const Step = enum {
    running,
    quit,
};

pub const Game = struct {
    allocator: std.mem.Allocator,
    world: world.World,
    objects: objects.WorldObjects,
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
    inventory: [inventory_capacity]InventoryEntry = [_]InventoryEntry{.{ .kind = .survey_blade, .count = 0 }} ** inventory_capacity,
    inventory_len: usize = 0,
    encounters: [encounters.max_encounters]Encounter = undefined,
    encounter_len: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !Game {
        return initWithSeed(allocator, world.randomSeed());
    }

    pub fn initWithSeed(allocator: std.mem.Allocator, seed: u64) !Game {
        var self = Game{
            .allocator = allocator,
            .world = try world.World.init(allocator, seed),
            .objects = objects.WorldObjects.init(allocator),
            .command_input = vaxis.widgets.TextInput.init(allocator),
        };
        errdefer self.world.deinit();
        errdefer self.objects.deinit();
        errdefer self.command_input.deinit();

        self.player_x = self.world.spawn.x;
        self.player_y = self.world.spawn.y;

        try self.seedStartingInventory();
        try self.seedWorldObjects();

        self.pushMessage("You cross into the machine-civilization's dead perimeter.", .{});
        self.pushMessage("Move with hjkl, WASD, or the arrow keys.", .{});
        self.pushMessage("Press q/g to pick up, e to interact, number keys to use items.", .{});
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
                self.pushMessage("Keys: q/g pickup, e interact, 1-0 use items, : commands.", .{});
                self.pushMessage("Commands: help, look, rest, where, inventory, clear, pickup, interact, use <slot>, quit.", .{});
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

    pub fn encounterAt(self: *const Game, x: i32, y: i32) ?Encounter {
        var i: usize = 0;
        while (i < self.encounter_len) : (i += 1) {
            const encounter = self.encounters[i];
            if (encounter.hp > 0 and encounter.coord.x == x and encounter.coord.y == y) return encounter;
        }
        return null;
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
        try self.addInventoryItem(.{ .kind = .survey_blade, .count = 1 });
        try self.addInventoryItem(.{ .kind = .filter_cloak, .count = 1 });
        try self.addInventoryItem(.{ .kind = .spark_rod, .count = 1 });
        try self.addInventoryItem(.{ .kind = .med_gel, .count = 1 });
        try self.addInventoryItem(.{ .kind = .transit_chart, .count = 1 });
        try self.addInventoryItem(.{ .kind = .lumen_cell, .count = 1 });
    }

    fn seedWorldObjects(self: *Game) !void {
        const spawn = self.currentCoord();
        try self.objects.putFeature(spawn, .{ .kind = .shelter_beacon });

        const cache_coord = self.findNearbyTerrain(spawn, 10, .ruins) orelse
            self.findNearbyTerrain(spawn, 10, .plains) orelse
            self.findNearbyWalkable(spawn, 10) orelse spawn;
        if (!std.meta.eql(cache_coord, spawn) or self.objects.featureAt(cache_coord) == null) {
            try self.objects.putFeature(cache_coord, .{ .kind = .sealed_cache });
        }

        const bush_coord = self.findNearbyTerrain(spawn, 12, .forest) orelse
            self.findNearbyTerrain(spawn, 12, .plains) orelse
            self.findNearbyWalkable(spawn, 12) orelse spawn;
        if (self.objects.featureAt(bush_coord) == null) {
            try self.objects.putFeature(bush_coord, .{ .kind = .fungal_garden });
        }

        const waypoint = self.findNearbyWalkable(self.world.objective, 6) orelse self.world.objective;
        if (self.objects.featureAt(waypoint) == null) {
            try self.objects.putFeature(waypoint, .{ .kind = .survey_pylon });
        }

        const ration_coord = self.findNearbyTerrain(spawn, 8, .hills) orelse
            self.findNearbyWalkable(spawn, 8) orelse spawn;
        if (self.objects.groundItemAt(ration_coord) == null) {
            try self.objects.putGroundItem(ration_coord, .{ .kind = .nutrient_paste, .count = 1 });
        }

        const salve_coord = self.findNearbyTerrain(spawn, 10, .marsh) orelse bush_coord;
        if (self.objects.groundItemAt(salve_coord) == null) {
            try self.objects.putGroundItem(salve_coord, .{ .kind = .reed_antitoxin, .count = 1 });
        }

        try self.seedProceduralPointsOfInterest(spawn);
        try self.seedProceduralPointsOfInterest(self.world.objective);
        try self.seedEncounters(spawn);
    }

    fn seedProceduralPointsOfInterest(self: *Game, origin: Coord) !void {
        const cell_size: i32 = 18;
        const min_cell = -@divFloor(generation.poi_search_radius, cell_size) - 1;
        const max_cell = @divFloor(generation.poi_search_radius, cell_size) + 1;

        var cy = min_cell;
        while (cy <= max_cell) : (cy += 1) {
            var cx = min_cell;
            while (cx <= max_cell) : (cx += 1) {
                const base_x = origin.x + cx * cell_size;
                const base_y = origin.y + cy * cell_size;
                const roll = generation.coordRoll(self.world.seed ^ 0x706f695f73656564, base_x, base_y);
                if (roll > 46) continue;

                const jitter_x: i32 = @intCast(generation.coordRoll(self.world.seed ^ 0x6a69747465725f78, base_x, base_y) % 13);
                const jitter_y: i32 = @intCast(generation.coordRoll(self.world.seed ^ 0x6a69747465725f79, base_x, base_y) % 13);
                const candidate = Coord{
                    .x = base_x + jitter_x - 6,
                    .y = base_y + jitter_y - 6,
                };
                if (encounters.distanceSquared(candidate, self.world.spawn) < 15 * 15) continue;
                if (encounters.distanceSquared(candidate, origin) > generation.poi_search_radius * generation.poi_search_radius) continue;
                if (!terrainWalkable(self.terrainAt(candidate.x, candidate.y))) continue;
                if (self.objects.featureAt(candidate) != null) continue;

                const feature = generation.featureFor(self.tileAt(candidate.x, candidate.y), roll);
                try self.objects.putFeature(candidate, .{ .kind = feature });

                if (generation.lootFor(self.world.seed, feature, candidate)) |loot| {
                    const loot_coord = self.findNearbyEmptyGround(candidate, 2) orelse candidate;
                    if (self.objects.groundItemAt(loot_coord) == null) {
                        try self.objects.putGroundItem(loot_coord, loot);
                    }
                }
            }
        }
    }

    fn seedEncounters(self: *Game, origin: Coord) !void {
        const cell_size: i32 = 24;
        var cy: i32 = -7;
        while (cy <= 7) : (cy += 1) {
            var cx: i32 = -7;
            while (cx <= 7) : (cx += 1) {
                const base_x = origin.x + cx * cell_size;
                const base_y = origin.y + cy * cell_size;
                const roll = generation.coordRoll(self.world.seed ^ 0x656e636f756e7465, base_x, base_y);
                if (roll > 38) continue;

                const coord = self.findNearbyWalkable(.{
                    .x = base_x + @as(i32, @intCast(roll % 11)) - 5,
                    .y = base_y + @as(i32, @intCast((roll / 3) % 11)) - 5,
                }, 5) orelse continue;
                if (encounters.distanceSquared(coord, self.world.spawn) < 20 * 20) continue;
                if (self.encounterAt(coord.x, coord.y) != null) continue;

                const kind = generation.encounterKindFor(self.tileAt(coord.x, coord.y), roll);
                try self.addEncounter(kind, coord);
            }
        }
    }

    fn addEncounter(self: *Game, kind: EncounterKind, coord: Coord) !void {
        if (self.encounter_len >= encounters.max_encounters) return error.TooManyEncounters;
        self.encounters[self.encounter_len] = .{
            .kind = kind,
            .coord = coord,
            .hp = encounters.maxHp(kind),
            .wake_turn = self.turn,
        };
        self.encounter_len += 1;
    }

    fn moveBy(self: *Game, dx: i2, dy: i2) void {
        const next_x = offsetAxis(self.player_x, dx);
        const next_y = offsetAxis(self.player_y, dy);

        const terrain = self.terrainAt(next_x, next_y);
        if (!terrainWalkable(terrain)) {
            self.pushMessage("The {s} turn you back.", .{terrainName(terrain)});
            return;
        }

        if (self.encounterIndexAt(.{ .x = next_x, .y = next_y })) |index| {
            self.bumpEncounter(index);
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
            .shelter_beacon => {
                self.spendTurn(0);
                self.hp = @min(max_hp, self.hp + 3);
                self.stamina = @min(max_stamina, self.stamina + 5);
                self.pushMessage("The shelter beacon warms your blood and steadies your suit seals.", .{});
            },
            .fungal_garden => {
                self.addInventoryItem(.{ .kind = .nutrient_paste, .count = 1 }) catch {
                    self.pushMessage("Your pack is too full to gather the edible growth.", .{});
                    return;
                };
                feature.depleted = true;
                self.spendTurn(0);
                self.pushMessage("You harvest clean fungal caps and pack them into nutrient paste.", .{});
            },
            .sealed_cache => {
                var added_gel = false;
                var added_vial = false;
                if (self.addInventoryItem(.{ .kind = .med_gel, .count = 1 })) |_| {
                    added_gel = true;
                } else |_| {}
                if (self.addInventoryItem(.{ .kind = .lumen_cell, .count = 1 })) |_| {
                    added_vial = true;
                } else |_| {}

                if (!added_gel and !added_vial) {
                    self.pushMessage("The cache is intact, but your pack has no room for it.", .{});
                    return;
                }

                feature.depleted = true;
                self.spendTurn(0);
                if (added_gel and added_vial) {
                    self.pushMessage("The cache yields med gel and a lumen cell.", .{});
                } else if (added_gel) {
                    self.pushMessage("The cache yields med gel before the rest has to stay behind.", .{});
                } else {
                    self.pushMessage("The cache yields a lumen cell before the rest has to stay behind.", .{});
                }
            },
            .survey_pylon => {
                self.spendTurn(0);
                self.pushMessage("The pylon resolves a blinking path toward the Watcher's Spire at {d},{d}.", .{
                    self.world.objective.x,
                    self.world.objective.y,
                });
            },
            .scavenger_camp => {
                if (self.hasItemWithTag(.salvage)) {
                    _ = self.consumeFirstItemWithTag(.salvage);
                    self.addInventoryItem(.{ .kind = .ruin_key, .count = 1 }) catch {
                        self.pushMessage("The camp offers a ruin key, but your pack is full.", .{});
                        return;
                    };
                    self.pushMessage("You trade machine scrap for a ruin key and a warning about patrol lights.", .{});
                } else {
                    self.addInventoryItem(.{ .kind = .nutrient_paste, .count = 1 }) catch {
                        self.pushMessage("The camp has supplies, but your pack is full.", .{});
                        return;
                    };
                    self.pushMessage("The camp is empty, but a sealed ration tube remains by the cooker.", .{});
                }
                feature.depleted = true;
                self.spendTurn(0);
            },
            .drone_hulk => {
                self.addInventoryItem(.{ .kind = .machine_scrap, .count = 2 }) catch {
                    self.pushMessage("The drone has salvage, but your pack is full.", .{});
                    return;
                };
                feature.depleted = true;
                self.spendTurn(1);
                self.pushMessage("You strip lenses and actuator bones from the drone hulk.", .{});
            },
            .coolant_spring => {
                self.addInventoryItem(.{ .kind = .reed_antitoxin, .count = 1 }) catch {
                    self.pushMessage("The coolant is clean, but you have no space to bottle it.", .{});
                    return;
                };
                feature.depleted = true;
                self.spendTurn(0);
                self.pushMessage("You bottle a bright dose of coolant-filtered antitoxin.", .{});
            },
            .cracked_archive => {
                if (self.hasItemWithTag(.map)) {
                    self.addInventoryItem(.{ .kind = .cipher_shard, .count = 1 }) catch {
                        self.pushMessage("A readable shard loosens, but your pack is full.", .{});
                        return;
                    };
                    self.pushMessage("Your chart indexes the archive; one cipher shard still has clean memory.", .{});
                } else {
                    self.pushMessage("The archive is readable only as weathered glass and old warning glyphs.", .{});
                }
                feature.depleted = true;
                self.spendTurn(0);
            },
            .prism_obelisk => {
                self.spendTurn(0);
                if (self.hasItem(.signal_mirror)) {
                    self.stamina = @min(max_stamina, self.stamina + 3);
                    self.pushMessage("Your signal mirror catches the obelisk's angle and the patrol beams become visible.", .{});
                } else {
                    self.pushMessage("The prism burns symbols into your vision. A signal mirror would make sense of it.", .{});
                }
            },
            .static_field => {
                if (self.hasItem(.phase_spike) or self.hasItem(.spark_rod)) {
                    if (self.hasItem(.phase_spike)) _ = self.consumeFirstItem(.phase_spike);
                    self.pushMessage("You ground the static field until its warning grid goes dark.", .{});
                } else {
                    self.hp = self.hp -| 4;
                    self.pushMessage("Static snaps through your boots before the field collapses.", .{});
                }
                feature.depleted = true;
                self.spendTurn(1);
            },
            .nanite_bloom => {
                if (self.hasItem(.filter_cloak)) {
                    self.addInventoryItem(.{ .kind = .machine_scrap, .count = 1 }) catch {
                        self.pushMessage("The bloom holds salvage, but your pack is full.", .{});
                        return;
                    };
                    self.pushMessage("Your filter cloak keeps the motes out while you skim useful machine dust.", .{});
                } else {
                    self.hp = self.hp -| 3;
                    self.pushMessage("Silver motes bite your skin before you shake them loose.", .{});
                }
                feature.depleted = true;
                self.spendTurn(1);
            },
            .collapsed_vault => {
                if (self.hasItem(.ruin_key)) {
                    _ = self.consumeFirstItem(.ruin_key);
                    self.addInventoryItem(.{ .kind = .gravitic_charm, .count = 1 }) catch {
                        self.pushMessage("The vault opens, but your pack cannot take the charm inside.", .{});
                        return;
                    };
                    self.pushMessage("The ruin key wakes the lock. A gravitic charm rolls into your palm.", .{});
                } else {
                    self.addInventoryItem(.{ .kind = .machine_scrap, .count = 1 }) catch {
                        self.pushMessage("You pry at the vault, but have no space for the scraps.", .{});
                        return;
                    };
                    self.pushMessage("Without a ruin key, you only pry loose a little machine scrap.", .{});
                }
                feature.depleted = true;
                self.spendTurn(1);
            },
            .relay_dais => {
                self.spendTurn(0);
                if (self.hasItem(.cipher_shard)) {
                    self.pushMessage("The relay answers your cipher shard with a route pulse toward {d},{d}.", .{
                        self.world.objective.x,
                        self.world.objective.y,
                    });
                } else {
                    self.pushMessage("The dais hums with traffic addressed to machines that are no longer listening.", .{});
                }
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
            .scan => {
                self.spendTurn(0);
                self.pushMessage("The {s} triangulates the spire: {d},{d}.", .{
                    def.name,
                    self.world.objective.x,
                    self.world.objective.y,
                });
                self.describeNearestSite();
            },
            .ward => {
                self.spendTurn(0);
                self.stamina = @min(max_stamina, self.stamina + 2);
                self.pushMessage("You tune the {s}; old hazard tones settle into a readable pattern.", .{def.name});
            },
            .cut_hazard => {
                const coord = self.currentCoord();
                if (self.objects.featurePtr(coord)) |feature| {
                    if (feature.kind == .static_field or feature.kind == .nanite_bloom) {
                        feature.depleted = true;
                        if (def.consumed_on_use) self.consumeInventorySlot(slot, 1);
                        self.spendTurn(0);
                        self.pushMessage("The {s} neutralizes the {s}.", .{ def.name, content.featureDef(feature.kind).name });
                        return;
                    }
                }
                self.pushMessage("The {s} needs an active hazard underfoot.", .{def.name});
            },
            .unlock => {
                const coord = self.currentCoord();
                if (self.objects.featurePtr(coord)) |feature| {
                    if (feature.kind == .collapsed_vault) {
                        feature.depleted = true;
                        if (def.consumed_on_use) self.consumeInventorySlot(slot, 1);
                        self.addInventoryItem(.{ .kind = .gravitic_charm, .count = 1 }) catch {
                            self.pushMessage("The vault opens, but your pack is full.", .{});
                            return;
                        };
                        self.spendTurn(0);
                        self.pushMessage("The {s} opens the collapsed vault cleanly.", .{def.name});
                        return;
                    }
                }
                self.pushMessage("The {s} does not find a lock here.", .{def.name});
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

    fn hasItem(self: *const Game, kind: ItemKind) bool {
        return self.findInventoryKind(kind) != null;
    }

    fn findInventoryKind(self: *const Game, kind: ItemKind) ?usize {
        var i: usize = 0;
        while (i < self.inventory_len) : (i += 1) {
            if (self.inventory[i].kind == kind) return i;
        }
        return null;
    }

    fn consumeFirstItem(self: *Game, kind: ItemKind) bool {
        if (self.findInventoryKind(kind)) |slot| {
            self.consumeInventorySlot(slot, 1);
            return true;
        }
        return false;
    }

    fn hasItemWithTag(self: *const Game, tag: content.ItemTag) bool {
        return self.findInventoryWithTag(tag) != null;
    }

    fn findInventoryWithTag(self: *const Game, tag: content.ItemTag) ?usize {
        var i: usize = 0;
        while (i < self.inventory_len) : (i += 1) {
            if (generation.itemHasTag(self.inventory[i].kind, tag)) return i;
        }
        return null;
    }

    fn consumeFirstItemWithTag(self: *Game, tag: content.ItemTag) bool {
        if (self.findInventoryWithTag(tag)) |slot| {
            self.consumeInventorySlot(slot, 1);
            return true;
        }
        return false;
    }

    fn spendTurn(self: *Game, stamina_cost: u16) void {
        self.turn += 1;
        self.stamina = self.stamina -| stamina_cost;
        if (self.turn % 5 == 0 and self.stamina < max_stamina) {
            self.stamina += 1;
        }
        self.updateEncounters();
    }

    fn announceArrival(self: *Game) void {
        if (self.encounterAt(self.player_x, self.player_y)) |encounter| {
            self.pushMessage("{s} presses close.", .{encounters.name(encounter.kind)});
        }
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

    fn describeNearestSite(self: *Game) void {
        var best_coord: ?Coord = null;
        var best_feature: ?FeatureState = null;
        var best_distance: i32 = std.math.maxInt(i32);

        var iterator = self.objects.features.iterator();
        while (iterator.next()) |entry| {
            const feature = entry.value_ptr.*;
            if (feature.depleted and content.featureDef(feature.kind).single_use) continue;
            const distance = encounters.distanceSquared(entry.key_ptr.*, self.currentCoord());
            if (distance > 0 and distance < best_distance) {
                best_distance = distance;
                best_coord = entry.key_ptr.*;
                best_feature = feature;
            }
        }

        if (best_coord) |coord| {
            const feature = best_feature.?;
            self.pushMessage("Nearest signal: {s} near {d},{d}.", .{
                content.featureDef(feature.kind).name,
                coord.x,
                coord.y,
            });
        }
    }

    fn bumpEncounter(self: *Game, index: usize) void {
        const encounter = &self.encounters[index];
        self.spendTurn(1);

        switch (encounter.kind) {
            .scavenger => {
                encounter.hp -= 3;
                if (encounter.hp <= 0) {
                    self.pushMessage("You drive off the scavenger and recover a strip of machine scrap.", .{});
                    self.addInventoryItem(.{ .kind = .machine_scrap, .count = 1 }) catch {};
                } else {
                    self.hp = self.hp -| 1;
                    self.pushMessage("A scavenger tests your guard, then slips aside.", .{});
                }
            },
            .survey_drone => {
                encounter.hp -= 2;
                self.stamina = self.stamina -| 1;
                self.pushMessage("The survey drone chirrs backward, mapping you with cold light.", .{});
            },
            .patrol_light => {
                self.hp = self.hp -| @as(u16, if (self.hasItem(.signal_mirror)) 1 else 3);
                encounter.wake_turn = self.turn + 3;
                self.pushMessage("The patrol light sweeps over you and burns a warning line into the dust.", .{});
            },
            .vault_guardian => {
                encounter.hp -= if (self.hasItem(.spark_rod)) 4 else 2;
                self.hp = self.hp -| 2;
                self.pushMessage("The vault guardian grinds forward on ancient servos.", .{});
            },
        }

        if (encounter.hp <= 0) {
            self.removeEncounter(index);
        }
    }

    fn updateEncounters(self: *Game) void {
        var i: usize = 0;
        while (i < self.encounter_len) : (i += 1) {
            if (self.encounters[i].wake_turn > self.turn) continue;

            const current = self.encounters[i].coord;
            const dx = encounters.signum(self.player_x - current.x);
            const dy = encounters.signum(self.player_y - current.y);
            var next = current;

            switch (self.encounters[i].kind) {
                .scavenger, .survey_drone, .vault_guardian => {
                    if (encounters.distanceSquared(current, self.currentCoord()) <= 18 * 18) {
                        if (@abs(self.player_x - current.x) >= @abs(self.player_y - current.y)) {
                            next.x += dx;
                        } else {
                            next.y += dy;
                        }
                    }
                },
                .patrol_light => {
                    next.x += if ((self.turn / 3 + @as(u32, @intCast(i))) % 2 == 0) 1 else -1;
                },
            }

            if (next.x == self.player_x and next.y == self.player_y) {
                self.resolveEncounterContact(i);
            } else if (terrainWalkable(self.terrainAt(next.x, next.y)) and self.encounterIndexAt(next) == null) {
                self.encounters[i].coord = next;
            }
        }
    }

    fn resolveEncounterContact(self: *Game, index: usize) void {
        const kind = self.encounters[index].kind;
        switch (kind) {
            .scavenger => self.hp = self.hp -| 1,
            .survey_drone => self.stamina = self.stamina -| 1,
            .patrol_light => self.hp = self.hp -| @as(u16, if (self.hasItem(.signal_mirror)) 1 else 3),
            .vault_guardian => self.hp = self.hp -| 2,
        }
        self.encounters[index].wake_turn = self.turn + 2;
        self.pushMessage("{s} catches up with you.", .{encounters.name(kind)});
    }

    fn encounterIndexAt(self: *const Game, coord: Coord) ?usize {
        var i: usize = 0;
        while (i < self.encounter_len) : (i += 1) {
            const encounter = self.encounters[i];
            if (encounter.hp > 0 and encounter.coord.x == coord.x and encounter.coord.y == coord.y) return i;
        }
        return null;
    }

    fn removeEncounter(self: *Game, index: usize) void {
        var i = index;
        while (i + 1 < self.encounter_len) : (i += 1) {
            self.encounters[i] = self.encounters[i + 1];
        }
        self.encounter_len -= 1;
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

    fn findNearbyEmptyGround(self: *Game, origin: Coord, radius: i32) ?Coord {
        var y = origin.y - radius;
        while (y <= origin.y + radius) : (y += 1) {
            var x = origin.x - radius;
            while (x <= origin.x + radius) : (x += 1) {
                const coord = Coord{ .x = x, .y = y };
                if (!terrainWalkable(self.terrainAt(coord.x, coord.y))) continue;
                if (self.objects.featureAt(coord) != null) continue;
                if (self.objects.groundItemAt(coord) != null) continue;
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

pub fn encounterName(kind: EncounterKind) []const u8 {
    return encounters.name(kind);
}

pub fn encounterGlyph(kind: EncounterKind) []const u8 {
    return encounters.glyph(kind);
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

test "procedural points of interest extend beyond the starter cluster" {
    var state = try Game.initWithSeed(std.testing.allocator, world.default_seed);
    defer state.deinit();

    var distant_sites: usize = 0;
    var ruin_sites: usize = 0;
    var iterator = state.objects.features.iterator();
    while (iterator.next()) |entry| {
        const coord = entry.key_ptr.*;
        if (encounters.distanceSquared(coord, state.world.spawn) > 24 * 24) distant_sites += 1;
        switch (entry.value_ptr.kind) {
            .cracked_archive, .collapsed_vault, .drone_hulk, .relay_dais, .static_field, .prism_obelisk => ruin_sites += 1,
            else => {},
        }
    }

    try std.testing.expect(distant_sites > 18);
    try std.testing.expect(ruin_sites > 3);
}

test "deterministic encounters are seeded away from spawn" {
    var first = try Game.initWithSeed(std.testing.allocator, world.default_seed);
    defer first.deinit();
    var second = try Game.initWithSeed(std.testing.allocator, world.default_seed);
    defer second.deinit();

    try std.testing.expect(first.encounter_len > 8);
    try std.testing.expectEqual(first.encounter_len, second.encounter_len);

    var i: usize = 0;
    while (i < first.encounter_len) : (i += 1) {
        try std.testing.expectEqual(first.encounters[i].kind, second.encounters[i].kind);
        try std.testing.expectEqual(first.encounters[i].coord, second.encounters[i].coord);
        try std.testing.expect(encounters.distanceSquared(first.encounters[i].coord, first.world.spawn) > 20 * 20);
    }
}
