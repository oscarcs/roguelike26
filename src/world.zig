const std = @import("std");

pub const chunk_size: usize = 64;
pub const chunk_size_i32: i32 = 64;
pub const default_seed: u64 = 0x26cafe5eed1234ab;

const chunk_cache_limit: usize = 96;
const atlas_cell_size: i32 = 96;
const atlas_cell_size_f32: f32 = 96.0;

pub const Terrain = enum(u8) {
    plains,
    forest,
    hills,
    marsh,
    ruins,
    river,
    water,
    mountain,
};

pub const Biome = enum(u8) {
    meadow,
    steppe,
    grove,
    deep_forest,
    fen,
    floodplain,
    rocky_lowlands,
    highlands,
    alpine,
    ruins,
    open_water,
};

pub const Cover = enum(u8) {
    bare,
    short_grass,
    tall_grass,
    flowers,
    scrub,
    tree,
    reeds,
    marsh_water,
    stones,
    rubble,
    current,
    deep_water,
};

pub const Region = enum(u8) {
    ember_fields,
    mistwood,
    glass_marsh,
    iron_ridge,
    dusk_road,
};

pub const Coord = struct {
    x: i32,
    y: i32,
};

pub const Tile = struct {
    terrain: Terrain,
    biome: Biome,
    cover: Cover,
    variation: u8,
    region: Region,
    elevation: u8,
    moisture: u8,
};

pub const RegionInfo = struct {
    name: []const u8,
    summary: []const u8,
    landmark: []const u8,
};

const RegionConfig = struct {
    region: Region,
    info: RegionInfo,
    elevation_bias: f32,
    moisture_bias: f32,
    ridge_bias: f32,
    forest_threshold_offset: f32,
    ruin_bonus: f32,
};

const region_configs = [_]RegionConfig{
    .{
        .region = .ember_fields,
        .info = .{
            .name = "Ember Fields",
            .summary = "Wind-cut grasslands, scattered stone circles, and dry hillocks surround the western approach.",
            .landmark = "Sunwheel stones rise above the yellow grass.",
        },
        .elevation_bias = 0.04,
        .moisture_bias = -0.11,
        .ridge_bias = 0.05,
        .forest_threshold_offset = 0.10,
        .ruin_bonus = 0.10,
    },
    .{
        .region = .mistwood,
        .info = .{
            .name = "Mistwood",
            .summary = "Dense tree cover and wet gullies create sheltered routes through the northern interior.",
            .landmark = "A ranger watchfire glows beneath the cedar canopy.",
        },
        .elevation_bias = 0.02,
        .moisture_bias = 0.19,
        .ridge_bias = 0.04,
        .forest_threshold_offset = -0.18,
        .ruin_bonus = -0.06,
    },
    .{
        .region = .glass_marsh,
        .info = .{
            .name = "Glass Marsh",
            .summary = "Flooded flats, reed beds, and silt-heavy channels spread across the southern basin.",
            .landmark = "The broken ferry hull rests in black water and reeds.",
        },
        .elevation_bias = -0.12,
        .moisture_bias = 0.26,
        .ridge_bias = -0.08,
        .forest_threshold_offset = 0.08,
        .ruin_bonus = -0.08,
    },
    .{
        .region = .iron_ridge,
        .info = .{
            .name = "Iron Ridge",
            .summary = "A bent mountain spine throws off rocky foothills, narrow saddles, and cold runoff.",
            .landmark = "A signal tower clings to the shale escarpment.",
        },
        .elevation_bias = 0.10,
        .moisture_bias = -0.05,
        .ridge_bias = 0.36,
        .forest_threshold_offset = 0.14,
        .ruin_bonus = -0.02,
    },
    .{
        .region = .dusk_road,
        .info = .{
            .name = "Dusk Road",
            .summary = "Broken roadbeds, terraces, and waystations trace the safer eastern passage toward the spire.",
            .landmark = "The Watcher's Spire cuts into the haze beyond the old road.",
        },
        .elevation_bias = 0.01,
        .moisture_bias = -0.03,
        .ridge_bias = 0.10,
        .forest_threshold_offset = 0.05,
        .ruin_bonus = 0.16,
    },
};

const ChunkCoord = struct {
    x: i32,
    y: i32,
};

const Chunk = struct {
    coord: ChunkCoord,
    tiles: [chunk_size][chunk_size]Tile,
    last_used: u64,
};

const RawTileGrid = [chunk_size + 2][chunk_size + 2]RawTile;

const ClimateSample = struct {
    elevation: f32,
    moisture: f32,
    ridge: f32,
};

const RawTile = struct {
    terrain: Terrain,
    region: Region,
    variation: u8,
    elevation: u8,
    moisture: u8,
};

pub const World = struct {
    allocator: std.mem.Allocator,
    seed: u64,
    chunks: std.AutoHashMap(ChunkCoord, *Chunk),
    tick: u64 = 0,
    spawn: Coord = .{ .x = 0, .y = 0 },
    objective: Coord = .{ .x = 240, .y = 0 },

    pub fn init(allocator: std.mem.Allocator, seed: u64) !World {
        var self = World{
            .allocator = allocator,
            .seed = seed,
            .chunks = std.AutoHashMap(ChunkCoord, *Chunk).init(allocator),
        };

        self.spawn = self.findSpawn();
        self.objective = self.findObjective(self.spawn);
        return self;
    }

    pub fn deinit(self: *World) void {
        var iterator = self.chunks.valueIterator();
        while (iterator.next()) |chunk_ptr| {
            self.allocator.destroy(chunk_ptr.*);
        }
        self.chunks.deinit();
    }

    pub fn tileAt(self: *World, x: i32, y: i32) Tile {
        const chunk = self.fetchChunkForCoord(x, y) catch unreachable;
        const local_x = localCoord(x);
        const local_y = localCoord(y);
        return chunk.tiles[local_y][local_x];
    }

    pub fn terrainAt(self: *World, x: i32, y: i32) Terrain {
        return self.tileAt(x, y).terrain;
    }

    pub fn biomeAt(self: *World, x: i32, y: i32) Biome {
        return self.tileAt(x, y).biome;
    }

    pub fn coverAt(self: *World, x: i32, y: i32) Cover {
        return self.tileAt(x, y).cover;
    }

    pub fn regionAt(self: *World, x: i32, y: i32) Region {
        return self.tileAt(x, y).region;
    }

    pub fn regionInfoAt(self: *World, x: i32, y: i32) RegionInfo {
        return regionInfo(self.regionAt(x, y));
    }

    fn fetchChunkForCoord(self: *World, x: i32, y: i32) !*Chunk {
        return self.fetchChunk(chunkCoordForWorld(x, y));
    }

    fn fetchChunk(self: *World, coord: ChunkCoord) !*Chunk {
        if (self.chunks.get(coord)) |chunk| {
            chunk.last_used = self.bumpTick();
            return chunk;
        }

        if (self.chunks.count() >= chunk_cache_limit) {
            self.evictOldestChunk();
        }

        const chunk = try self.allocator.create(Chunk);
        chunk.* = .{
            .coord = coord,
            .tiles = undefined,
            .last_used = self.bumpTick(),
        };
        self.populateChunk(chunk);
        try self.chunks.put(coord, chunk);
        return chunk;
    }

    fn populateChunk(self: *World, chunk: *Chunk) void {
        const origin_x = chunk.coord.x * chunk_size_i32;
        const origin_y = chunk.coord.y * chunk_size_i32;
        var raw_tiles: RawTileGrid = undefined;

        for (0..chunk_size + 2) |raw_y_idx| {
            const world_y = origin_y + @as(i32, @intCast(raw_y_idx)) - 1;
            for (0..chunk_size + 2) |raw_x_idx| {
                const world_x = origin_x + @as(i32, @intCast(raw_x_idx)) - 1;
                raw_tiles[raw_y_idx][raw_x_idx] = sampleRawTile(self.seed, world_x, world_y);
            }
        }

        for (0..chunk_size) |y_idx| {
            const world_y = origin_y + @as(i32, @intCast(y_idx));
            for (0..chunk_size) |x_idx| {
                const world_x = origin_x + @as(i32, @intCast(x_idx));
                chunk.tiles[y_idx][x_idx] = synthesizeTileFromRawGrid(
                    self.seed,
                    world_x,
                    world_y,
                    &raw_tiles,
                    x_idx + 1,
                    y_idx + 1,
                );
            }
        }
    }

    fn evictOldestChunk(self: *World) void {
        var iterator = self.chunks.iterator();
        var oldest_coord: ?ChunkCoord = null;
        var oldest_tick: u64 = std.math.maxInt(u64);

        while (iterator.next()) |entry| {
            if (entry.value_ptr.*.last_used < oldest_tick) {
                oldest_tick = entry.value_ptr.*.last_used;
                oldest_coord = entry.key_ptr.*;
            }
        }

        if (oldest_coord) |coord| {
            const chunk = self.chunks.fetchRemove(coord).?.value;
            self.allocator.destroy(chunk);
        }
    }

    fn bumpTick(self: *World) u64 {
        self.tick +%= 1;
        return self.tick;
    }

    fn findSpawn(self: *World) Coord {
        var best = Coord{ .x = -24, .y = 0 };
        var best_score: i32 = std.math.minInt(i32);

        var y: i32 = -54;
        while (y <= 54) : (y += 1) {
            var x: i32 = -48;
            while (x <= 24) : (x += 1) {
                const coord = Coord{ .x = x, .y = y };
                const tile = self.tileAt(coord.x, coord.y);
                if (!terrainWalkable(tile.terrain)) continue;

                var score: i32 = 0;
                score -= @as(i32, @intCast(@abs(coord.x))) * 2;
                score -= @as(i32, @intCast(@abs(coord.y)));
                score += 12 * @as(i32, countAdjacentWalkable(self, coord));
                score -= 16 * @as(i32, countAdjacent(self, coord, .water));

                switch (tile.terrain) {
                    .plains => score += 32,
                    .forest => score += 20,
                    .ruins => score += 26,
                    .hills => score += 8,
                    .marsh, .river => score -= 10,
                    else => {},
                }

                if (tile.region == .ember_fields or tile.region == .mistwood) score += 10;

                if (score > best_score) {
                    best = coord;
                    best_score = score;
                }
            }
        }

        return best;
    }

    fn findObjective(self: *World, spawn: Coord) Coord {
        var best = Coord{ .x = spawn.x + 240, .y = @intFromFloat(@round(roadCenter(self.seed, spawn.x + 240))) };
        var best_score: i32 = std.math.minInt(i32);

        var y: i32 = spawn.y - 72;
        while (y <= spawn.y + 72) : (y += 1) {
            var x: i32 = spawn.x + 180;
            while (x <= spawn.x + 320) : (x += 1) {
                const coord = Coord{ .x = x, .y = y };
                const tile = self.tileAt(coord.x, coord.y);
                if (!terrainWalkable(tile.terrain)) continue;

                var score: i32 = coord.x - spawn.x;
                score -= @as(i32, @intCast(@abs(coord.y - @as(i32, @intFromFloat(@round(roadCenter(self.seed, coord.x))))))) * 2;
                score += 8 * @as(i32, countAdjacentWalkable(self, coord));

                if (tile.region == .dusk_road) score += 56;
                switch (tile.terrain) {
                    .ruins => score += 36,
                    .hills => score += 18,
                    .plains => score += 10,
                    .forest => score += 2,
                    .river, .marsh => score -= 12,
                    else => {},
                }

                if (score > best_score) {
                    best = coord;
                    best_score = score;
                }
            }
        }

        return best;
    }
};

pub fn randomSeed() u64 {
    var seed = std.crypto.random.int(u64);
    if (seed == 0) seed = default_seed;
    return seed;
}

pub fn regionInfo(region: Region) RegionInfo {
    return configForRegion(region).info;
}

pub fn biomeName(biome: Biome) []const u8 {
    return switch (biome) {
        .meadow => "meadow",
        .steppe => "steppe",
        .grove => "grove",
        .deep_forest => "deep forest",
        .fen => "fen",
        .floodplain => "floodplain",
        .rocky_lowlands => "rocky lowlands",
        .highlands => "highlands",
        .alpine => "alpine slopes",
        .ruins => "ruined ground",
        .open_water => "open water",
    };
}

pub fn coverName(cover: Cover) []const u8 {
    return switch (cover) {
        .bare => "bare ground",
        .short_grass => "short grass",
        .tall_grass => "tall grass",
        .flowers => "wildflowers",
        .scrub => "scrub",
        .tree => "tree cover",
        .reeds => "reeds",
        .marsh_water => "stagnant water",
        .stones => "stones",
        .rubble => "rubble",
        .current => "running water",
        .deep_water => "deep water",
    };
}

pub fn terrainName(terrain: Terrain) []const u8 {
    return switch (terrain) {
        .plains => "open plains",
        .forest => "forest",
        .hills => "rolling hills",
        .marsh => "marshland",
        .ruins => "fallen ruins",
        .river => "river crossing",
        .water => "deep water",
        .mountain => "mountain wall",
    };
}

pub fn terrainWalkable(terrain: Terrain) bool {
    return switch (terrain) {
        .water, .mountain => false,
        else => true,
    };
}

pub fn movementCost(terrain: Terrain) u16 {
    return switch (terrain) {
        .hills, .marsh, .river => 2,
        else => 1,
    };
}

fn configForRegion(region: Region) *const RegionConfig {
    return &region_configs[@intFromEnum(region)];
}

fn synthesizeTile(seed: u64, x: i32, y: i32) Tile {
    var raw = sampleRawTile(seed, x, y);

    if (raw.terrain != .water and raw.terrain != .mountain and raw.terrain != .river) {
        const wet_neighbors = rawAdjacentCount(seed, x, y, .water) + rawAdjacentCount(seed, x, y, .river);
        if (wet_neighbors >= 2 and raw.elevation < 132 and raw.terrain != .ruins) {
            raw.terrain = .marsh;
            raw.moisture = @max(raw.moisture, 190);
        } else if (wet_neighbors >= 1 and raw.terrain == .plains and raw.moisture > 150) {
            raw.terrain = .forest;
        }
    }

    const biome = classifyBiome(raw.region, raw.terrain, raw.elevation, raw.moisture);
    const cover = classifyCover(seed, biome, raw.terrain, x, y, raw.elevation, raw.moisture);

    return .{
        .terrain = raw.terrain,
        .biome = biome,
        .cover = cover,
        .variation = raw.variation,
        .region = raw.region,
        .elevation = raw.elevation,
        .moisture = raw.moisture,
    };
}

fn synthesizeTileFromRawGrid(seed: u64, x: i32, y: i32, raw_tiles: *const RawTileGrid, raw_x: usize, raw_y: usize) Tile {
    var raw = raw_tiles.*[raw_y][raw_x];

    if (raw.terrain != .water and raw.terrain != .mountain and raw.terrain != .river) {
        const wet_neighbors = rawAdjacentCountFromGrid(raw_tiles, raw_x, raw_y, .water) +
            rawAdjacentCountFromGrid(raw_tiles, raw_x, raw_y, .river);
        if (wet_neighbors >= 2 and raw.elevation < 132 and raw.terrain != .ruins) {
            raw.terrain = .marsh;
            raw.moisture = @max(raw.moisture, 190);
        } else if (wet_neighbors >= 1 and raw.terrain == .plains and raw.moisture > 150) {
            raw.terrain = .forest;
        }
    }

    const biome = classifyBiome(raw.region, raw.terrain, raw.elevation, raw.moisture);
    const cover = classifyCover(seed, biome, raw.terrain, x, y, raw.elevation, raw.moisture);

    return .{
        .terrain = raw.terrain,
        .biome = biome,
        .cover = cover,
        .variation = raw.variation,
        .region = raw.region,
        .elevation = raw.elevation,
        .moisture = raw.moisture,
    };
}

fn sampleRawTile(seed: u64, x: i32, y: i32) RawTile {
    const variation = variationForCoord(seed, x, y);
    const base_climate = sampleBaseClimate(seed, x, y);
    const region = selectRegion(seed, base_climate, x, y);
    const config = configForRegion(region);
    const climate = applyRegionBias(base_climate, config);

    var terrain = classifyTerrain(seed, config, climate, x, y);
    var elevation = toByte(climate.elevation);
    var moisture = toByte(climate.moisture);

    const road_distance = roadDistance(seed, x, y);
    if (region == .dusk_road and road_distance < 2.2 and terrain != .river) {
        terrain = if (climate.moisture > 0.48 and climate.elevation < 0.58) .plains else .ruins;
        elevation = @min(elevation, 168);
        moisture = @min(moisture, 160);
    } else if (region == .dusk_road and road_distance < 5.0 and (terrain == .water or terrain == .mountain)) {
        terrain = .plains;
        elevation = @min(elevation, 172);
        moisture = @min(moisture, 150);
    }

    const river_strength = riverStrength(seed, x, y);
    if (terrain != .mountain and road_distance > 1.5 and climate.elevation > 0.29 and climate.elevation < 0.80 and climate.moisture > 0.42) {
        if (river_strength > 0.94 and climate.elevation < 0.40) {
            terrain = .water;
            elevation = @min(elevation, 76);
            moisture = @max(moisture, 210);
        } else if (river_strength > 0.84) {
            terrain = .river;
            elevation = @min(elevation, 168);
            moisture = @max(moisture, 210);
        }
    }

    if (terrain == .water) {
        elevation = @min(elevation, 76);
        moisture = @max(moisture, 210);
    }

    return .{
        .terrain = terrain,
        .region = region,
        .variation = variation,
        .elevation = elevation,
        .moisture = moisture,
    };
}

fn sampleBaseClimate(seed: u64, x: i32, y: i32) ClimateSample {
    const fx = coordScale(x, 320.0);
    const fy = coordScale(y, 280.0);
    const warp_x = fx + (fractalNoise(seed ^ 0x9989d3f1bb39f243, fx * 0.95, fy * 0.95, 3, 2.0, 0.5) - 0.5) * 0.42;
    const warp_y = fy + (fractalNoise(seed ^ 0x7b1f7cf8e812d4c1, fx * 0.95, fy * 0.95, 3, 2.0, 0.5) - 0.5) * 0.38;

    const continental = fractalNoise(seed ^ 0x4137ba5dc9185f1f, warp_x * 1.10, warp_y * 1.00, 4, 2.0, 0.52);
    const relief = fractalNoise(seed ^ 0xa2d4d0c5e45c1d77, warp_x * 3.30, warp_y * 3.30, 3, 2.2, 0.55);
    const moisture_base = fractalNoise(seed ^ 0x51f12d6efc2fb6d3, warp_x * 1.25, warp_y * 1.35, 4, 2.0, 0.54);
    const moisture_detail = fractalNoise(seed ^ 0x8cf0e0fb2f50a991, warp_x * 3.80, warp_y * 3.60, 2, 2.0, 0.5);

    const ridge_center = (fractalNoise(seed ^ 0xee7cb53129b2b4e7, warp_x * 0.72, 0.0, 3, 2.0, 0.5) - 0.5) * 1.25;
    const ridge_distance = @abs(warp_y - ridge_center);
    const ridge_band = clamp01(1.0 - ridge_distance / 0.22);
    const ridge = ridge_band * ridge_band;

    const basin = fractalNoise(seed ^ 0x1ac0f1d7e96c4b2d, warp_x * 0.90, warp_y * 0.90, 3, 2.0, 0.5);
    const basin_cut = smoothstep(0.70, 0.98, basin) * 0.22;

    var elevation = 0.16 + continental * 0.48 + relief * 0.18 + ridge * 0.18 - basin_cut;
    var moisture = 0.28 + moisture_base * 0.48 + moisture_detail * 0.12;
    if (ridge > 0.32) moisture -= ridge * 0.10;

    elevation = clamp01(elevation);
    moisture = clamp01(moisture);

    return .{
        .elevation = elevation,
        .moisture = moisture,
        .ridge = ridge,
    };
}

fn applyRegionBias(base: ClimateSample, config: *const RegionConfig) ClimateSample {
    const elevation = base.elevation + config.elevation_bias + base.ridge * config.ridge_bias * 0.42;
    var moisture = base.moisture + config.moisture_bias;
    if (base.ridge > 0.32) moisture -= base.ridge * 0.08;

    return .{
        .elevation = clamp01(elevation),
        .moisture = clamp01(moisture),
        .ridge = base.ridge,
    };
}

fn selectRegion(seed: u64, climate: ClimateSample, x: i32, y: i32) Region {
    const road_distance = roadDistance(seed, x, y);
    if (road_distance < 6.5 and x > -48) return .dusk_road;

    const cell_x = @divFloor(x, atlas_cell_size);
    const cell_y = @divFloor(y, atlas_cell_size);
    var best = Region.ember_fields;
    var best_score = std.math.inf(f32);

    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            const atlas_x = cell_x + dx;
            const atlas_y = cell_y + dy;
            const candidate = atlasRegion(seed, atlas_x, atlas_y);
            const center_x = (@as(f32, @floatFromInt(atlas_x)) + 0.5) * atlas_cell_size_f32 + atlasJitter(seed ^ 0x8c0f24f1ad0ea76b, atlas_x, atlas_y);
            const center_y = (@as(f32, @floatFromInt(atlas_y)) + 0.5) * atlas_cell_size_f32 + atlasJitter(seed ^ 0x3b6d0fca0de6b785, atlas_x, atlas_y);
            const delta_x = @as(f32, @floatFromInt(x)) - center_x;
            const delta_y = @as(f32, @floatFromInt(y)) - center_y;
            const distance_score = delta_x * delta_x + delta_y * delta_y;
            const total_score = distance_score + regionPenalty(candidate, climate, road_distance);

            if (total_score < best_score) {
                best_score = total_score;
                best = candidate;
            }
        }
    }

    return best;
}

fn atlasRegion(seed: u64, cell_x: i32, cell_y: i32) Region {
    return switch (mix(seed ^ 0x5ad26b9f67bbd271, cell_x, cell_y) & 3) {
        0 => .ember_fields,
        1 => .mistwood,
        2 => .glass_marsh,
        else => .iron_ridge,
    };
}

fn atlasJitter(seed: u64, cell_x: i32, cell_y: i32) f32 {
    return (hash01(seed, cell_x, cell_y) - 0.5) * @as(f32, @floatFromInt(atlas_cell_size)) * 0.55;
}

fn regionPenalty(region: Region, climate: ClimateSample, road_distance: f32) f32 {
    return switch (region) {
        .ember_fields => climate.moisture * 1450.0 + climate.ridge * 340.0,
        .mistwood => @abs(climate.moisture - 0.68) * 800.0 + climate.ridge * 180.0,
        .glass_marsh => @abs(climate.moisture - 0.82) * 700.0 + @abs(climate.elevation - 0.30) * 1000.0,
        .iron_ridge => @abs(climate.elevation - 0.76) * 900.0 + @abs(climate.ridge - 0.72) * 850.0,
        .dusk_road => road_distance * 80.0,
    };
}

fn classifyTerrain(seed: u64, config: *const RegionConfig, climate: ClimateSample, x: i32, y: i32) Terrain {
    const region_index: f32 = @floatFromInt(@intFromEnum(config.region));
    const ruin_noise = fractalNoise(
        seed ^ 0xd93b4f5a8b1f9c73,
        coordScale(x, 38.0) + region_index * 0.5,
        coordScale(y, 38.0) - region_index * 0.5,
        2,
        2.0,
        0.5,
    );

    if (climate.elevation < 0.28) return .water;
    if (climate.elevation > 0.82 or climate.ridge > 0.86) return .mountain;
    if (climate.elevation > 0.66 or climate.ridge > 0.56) return .hills;
    if (climate.moisture > 0.75 and climate.elevation < 0.47) return .marsh;
    if (climate.moisture > 0.61 + config.forest_threshold_offset and climate.elevation < 0.72) return .forest;
    if (ruin_noise > 0.88 - config.ruin_bonus and climate.elevation > 0.38 and climate.elevation < 0.67) return .ruins;
    return .plains;
}

fn classifyBiome(region: Region, terrain: Terrain, elevation: u8, moisture: u8) Biome {
    const elevation_unit = byteToUnit(elevation);
    const moisture_unit = byteToUnit(moisture);

    return switch (terrain) {
        .water => .open_water,
        .river => .floodplain,
        .marsh => .fen,
        .ruins => .ruins,
        .mountain => .alpine,
        .hills => if (elevation_unit > 0.76) .alpine else .highlands,
        .forest => switch (region) {
            .mistwood => if (moisture_unit > 0.72) .deep_forest else .grove,
            .glass_marsh => .floodplain,
            else => if (moisture_unit > 0.66) .deep_forest else .grove,
        },
        .plains => switch (region) {
            .glass_marsh => if (moisture_unit > 0.56) .floodplain else .meadow,
            .iron_ridge => if (elevation_unit > 0.58) .rocky_lowlands else .steppe,
            .dusk_road => if (moisture_unit < 0.38) .steppe else .meadow,
            .ember_fields => if (moisture_unit < 0.34) .steppe else .meadow,
            .mistwood => if (moisture_unit > 0.58) .grove else .meadow,
        },
    };
}

fn classifyCover(seed: u64, biome: Biome, terrain: Terrain, x: i32, y: i32, elevation: u8, moisture: u8) Cover {
    const detail = variationForCoord(seed ^ 0x91f24563dd8c27a1, x, y);
    const elevation_unit = byteToUnit(elevation);
    const moisture_unit = byteToUnit(moisture);

    return switch (terrain) {
        .water => .deep_water,
        .river => .current,
        .marsh => if (detail < 112) .reeds else if (detail < 224) .marsh_water else .current,
        .mountain => if (detail < 180) .stones else .bare,
        .ruins => if (detail < 150) .rubble else .stones,
        .hills => switch (biome) {
            .alpine => if (detail < 170) .stones else .bare,
            .highlands => if (detail < 84) .short_grass else if (detail < 104 and moisture_unit > 0.36) .tree else if (detail < 176) .stones else .scrub,
            else => if (detail < 128) .short_grass else .scrub,
        },
        .forest => switch (biome) {
            .deep_forest => if (detail < 208) .tree else .scrub,
            .floodplain => if (detail < 144) .tree else .reeds,
            else => if (detail < 176) .tree else if (detail < 220) .tall_grass else .scrub,
        },
        .plains => switch (biome) {
            .meadow => if (detail < 76) .short_grass else if (detail < 136) .tall_grass else if (detail < 148 and moisture_unit > 0.40) .tree else if (detail < 190 and moisture_unit > 0.40) .flowers else .scrub,
            .steppe => if (detail < 96) .short_grass else if (detail < 204) .scrub else if (detail < 212 and moisture_unit > 0.34) .tree else .bare,
            .floodplain => if (detail < 112) .tall_grass else if (detail < 188) .reeds else if (detail < 214) .tree else .flowers,
            .rocky_lowlands => if (detail < 90) .short_grass else if (detail < 108 and moisture_unit > 0.34 and elevation_unit < 0.60) .tree else if (detail < 180 or elevation_unit > 0.60) .stones else .scrub,
            .grove => if (detail < 104) .short_grass else if (detail < 168) .tall_grass else if (detail < 216) .tree else .flowers,
            else => if (detail < 128) .short_grass else .scrub,
        },
    };
}

fn roadCenter(seed: u64, x: i32) f32 {
    const fx = coordScale(x, 180.0);
    const broad = (fractalNoise(seed ^ 0x8215f4206d55ca7d, fx * 0.90, 0.0, 3, 2.0, 0.5) - 0.5) * 54.0;
    const detail = (fractalNoise(seed ^ 0x58c3db5129037e41, fx * 2.90, 0.0, 2, 2.0, 0.5) - 0.5) * 16.0;
    return broad + detail;
}

fn roadDistance(seed: u64, x: i32, y: i32) f32 {
    return @abs(@as(f32, @floatFromInt(y)) - roadCenter(seed, x));
}

fn riverStrength(seed: u64, x: i32, y: i32) f32 {
    const fx = coordScale(x, 84.0);
    const fy = coordScale(y, 84.0);
    const warp_x = fx + (fractalNoise(seed ^ 0x1134fbc91c87dd21, fx * 1.10, fy * 1.10, 2, 2.0, 0.5) - 0.5) * 0.34;
    const warp_y = fy + (fractalNoise(seed ^ 0x6d9c4d8e4d6f5177, fx * 1.10, fy * 1.10, 2, 2.0, 0.5) - 0.5) * 0.34;
    const a = fractalNoise(seed ^ 0xa1f5267ec4fb0d4f, warp_x * 1.20, warp_y * 1.20, 3, 2.0, 0.5);
    const b = fractalNoise(seed ^ 0xd5b2ad5213ef4cb9, warp_x * 0.62 + 11.7, warp_y * 0.62 - 7.3, 2, 2.0, 0.5);
    const line = @abs(a - b);
    return 1.0 - clamp01(line * 9.0);
}

fn rawAdjacentCount(seed: u64, x: i32, y: i32, terrain: Terrain) u8 {
    var count: u8 = 0;
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;
            if (sampleRawTile(seed, x + dx, y + dy).terrain == terrain) count += 1;
        }
    }
    return count;
}

fn rawAdjacentCountFromGrid(raw_tiles: *const RawTileGrid, raw_x: usize, raw_y: usize, terrain: Terrain) u8 {
    var count: u8 = 0;
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;

            const sample_x: usize = @intCast(@as(i32, @intCast(raw_x)) + dx);
            const sample_y: usize = @intCast(@as(i32, @intCast(raw_y)) + dy);
            if (raw_tiles.*[sample_y][sample_x].terrain == terrain) count += 1;
        }
    }
    return count;
}

fn countAdjacent(self: *World, coord: Coord, terrain: Terrain) u8 {
    var count: u8 = 0;
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;
            if (self.terrainAt(coord.x + dx, coord.y + dy) == terrain) count += 1;
        }
    }
    return count;
}

fn countAdjacentWalkable(self: *World, coord: Coord) u8 {
    var count: u8 = 0;
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;
            if (terrainWalkable(self.terrainAt(coord.x + dx, coord.y + dy))) count += 1;
        }
    }
    return count;
}

fn chunkCoordForWorld(x: i32, y: i32) ChunkCoord {
    return .{
        .x = @divFloor(x, chunk_size_i32),
        .y = @divFloor(y, chunk_size_i32),
    };
}

fn localCoord(value: i32) usize {
    return @intCast(@mod(value, chunk_size_i32));
}

fn coordScale(value: i32, scale: f32) f32 {
    return @as(f32, @floatFromInt(value)) / scale;
}

fn variationForCoord(seed: u64, x: i32, y: i32) u8 {
    return @intCast((mix(seed ^ 0x6a09e667f3bcc909, x, y) >> 56) & 0xff);
}

fn toByte(value: f32) u8 {
    const clamped = clamp01(value);
    return @intFromFloat(clamped * 255.0);
}

fn byteToUnit(value: u8) f32 {
    return @as(f32, @floatFromInt(value)) / 255.0;
}

fn clamp01(value: f32) f32 {
    return std.math.clamp(value, 0.0, 1.0);
}

fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn smoothstep(edge0: f32, edge1: f32, value: f32) f32 {
    if (edge0 == edge1) return if (value < edge0) 0.0 else 1.0;
    const t = clamp01((value - edge0) / (edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
}

fn fractalNoise(seed: u64, x: f32, y: f32, octaves: u8, lacunarity: f32, gain: f32) f32 {
    var amplitude: f32 = 0.5;
    var frequency: f32 = 1.0;
    var total: f32 = 0.0;
    var normalizer: f32 = 0.0;
    var octave: u8 = 0;

    while (octave < octaves) : (octave += 1) {
        total += valueNoise(seed +% (@as(u64, octave + 1) *% 0x9e3779b97f4a7c15), x * frequency, y * frequency) * amplitude;
        normalizer += amplitude;
        amplitude *= gain;
        frequency *= lacunarity;
    }

    return if (normalizer == 0.0) 0.0 else total / normalizer;
}

fn valueNoise(seed: u64, x: f32, y: f32) f32 {
    const ix: i32 = @intFromFloat(@floor(x));
    const iy: i32 = @intFromFloat(@floor(y));
    const tx = smoothstep(0.0, 1.0, x - @as(f32, @floatFromInt(ix)));
    const ty = smoothstep(0.0, 1.0, y - @as(f32, @floatFromInt(iy)));

    const v00 = hash01(seed, ix, iy);
    const v10 = hash01(seed, ix + 1, iy);
    const v01 = hash01(seed, ix, iy + 1);
    const v11 = hash01(seed, ix + 1, iy + 1);

    const a = lerp(v00, v10, tx);
    const b = lerp(v01, v11, tx);
    return lerp(a, b, ty);
}

fn hash01(seed: u64, x: i32, y: i32) f32 {
    const value = mix(seed, x, y);
    const top = value >> 40;
    return @as(f32, @floatFromInt(top)) / 16777215.0;
}

fn mix(seed: u64, x: i32, y: i32) u64 {
    const ux: u64 = @bitCast(@as(i64, x));
    const uy: u64 = @bitCast(@as(i64, y));

    var value = seed ^ (ux *% 0x9e3779b97f4a7c15) ^ (uy *% 0xc2b2ae3d27d4eb4f);
    value ^= value >> 30;
    value *%= 0xbf58476d1ce4e5b9;
    value ^= value >> 27;
    value *%= 0x94d049bb133111eb;
    value ^= value >> 31;
    return value;
}

test "world generation stays deterministic across chunks" {
    var first = try World.init(std.testing.allocator, default_seed);
    defer first.deinit();

    var second = try World.init(std.testing.allocator, default_seed);
    defer second.deinit();

    try std.testing.expectEqual(first.spawn, second.spawn);
    try std.testing.expectEqual(first.objective, second.objective);

    const sample_points = [_]Coord{
        .{ .x = -130, .y = -80 },
        .{ .x = -64, .y = -1 },
        .{ .x = 0, .y = 0 },
        .{ .x = 63, .y = 64 },
        .{ .x = 192, .y = -37 },
        .{ .x = 287, .y = 144 },
    };

    for (sample_points) |coord| {
        try std.testing.expectEqualDeep(first.tileAt(coord.x, coord.y), second.tileAt(coord.x, coord.y));
    }
}

test "world generation remains feature rich near the starting frontier" {
    var generated = try World.init(std.testing.allocator, default_seed);
    defer generated.deinit();

    var water: usize = 0;
    var forest: usize = 0;
    var river: usize = 0;
    var mountain: usize = 0;
    var marsh_water: usize = 0;
    var plains_tree: usize = 0;
    const sample_width: usize = 160;
    const sample_height: usize = 120;

    var row: usize = 0;
    while (row < sample_height) : (row += 1) {
        const y = generated.spawn.y - 50 + @as(i32, @intCast(row));
        var col: usize = 0;
        while (col < sample_width) : (col += 1) {
            const x = generated.spawn.x - 60 + @as(i32, @intCast(col));
            const tile = generated.tileAt(x, y);
            switch (tile.terrain) {
                .water => water += 1,
                .forest => forest += 1,
                .river => river += 1,
                .mountain => mountain += 1,
                else => {},
            }
            if (tile.cover == .marsh_water) marsh_water += 1;
            if (tile.terrain == .plains and tile.cover == .tree) plains_tree += 1;
        }
    }

    const total_tiles = sample_width * sample_height;

    try std.testing.expect(water > total_tiles / 80);
    try std.testing.expect(forest > total_tiles / 20);
    try std.testing.expect(river > total_tiles / 280);
    try std.testing.expect(mountain > total_tiles / 90);
    try std.testing.expect(marsh_water > total_tiles / 700);
    try std.testing.expect(plains_tree > total_tiles / 1400);
    try std.testing.expect(terrainWalkable(generated.terrainAt(generated.spawn.x, generated.spawn.y)));
    try std.testing.expect(generated.objective.x > generated.spawn.x);
}

test "chunk synthesis reuses raw samples without changing tile output" {
    const seed = default_seed;
    const coord = ChunkCoord{ .x = 2, .y = -1 };
    const origin_x = coord.x * chunk_size_i32;
    const origin_y = coord.y * chunk_size_i32;
    var raw_tiles: RawTileGrid = undefined;

    for (0..chunk_size + 2) |raw_y_idx| {
        const world_y = origin_y + @as(i32, @intCast(raw_y_idx)) - 1;
        for (0..chunk_size + 2) |raw_x_idx| {
            const world_x = origin_x + @as(i32, @intCast(raw_x_idx)) - 1;
            raw_tiles[raw_y_idx][raw_x_idx] = sampleRawTile(seed, world_x, world_y);
        }
    }

    for (0..chunk_size) |y_idx| {
        const world_y = origin_y + @as(i32, @intCast(y_idx));
        for (0..chunk_size) |x_idx| {
            const world_x = origin_x + @as(i32, @intCast(x_idx));
            try std.testing.expectEqualDeep(
                synthesizeTile(seed, world_x, world_y),
                synthesizeTileFromRawGrid(seed, world_x, world_y, &raw_tiles, x_idx + 1, y_idx + 1),
            );
        }
    }
}
