const std = @import("std");

pub const width: usize = 256;
pub const height: usize = 160;
pub const width_u16: u16 = 256;
pub const height_u16: u16 = 160;
pub const default_seed: u64 = 0x26cafe5eed1234ab;

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
    x: u16,
    y: u16,
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
    anchor: Coord,
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
        .anchor = .{ .x = width_u16 * 14 / 100, .y = height_u16 * 31 / 100 },
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
        .anchor = .{ .x = width_u16 * 30 / 100, .y = height_u16 * 20 / 100 },
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
        .anchor = .{ .x = width_u16 * 43 / 100, .y = height_u16 * 78 / 100 },
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
        .anchor = .{ .x = width_u16 * 69 / 100, .y = height_u16 * 23 / 100 },
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
        .anchor = .{ .x = width_u16 * 86 / 100, .y = height_u16 * 59 / 100 },
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

pub const World = struct {
    seed: u64,
    tiles: [height][width]Tile = undefined,
    spawn: Coord = .{ .x = 6, .y = height_u16 / 2 },
    objective: Coord = .{ .x = width_u16 - 10, .y = height_u16 / 2 },

    pub fn init(seed: u64) World {
        var self = World{ .seed = seed };
        self.generate();
        return self;
    }

    pub fn tileAt(self: *const World, x: u16, y: u16) Tile {
        return self.tiles[@as(usize, y)][@as(usize, x)];
    }

    pub fn terrainAt(self: *const World, x: u16, y: u16) Terrain {
        return self.tileAt(x, y).terrain;
    }

    pub fn biomeAt(self: *const World, x: u16, y: u16) Biome {
        return self.tileAt(x, y).biome;
    }

    pub fn coverAt(self: *const World, x: u16, y: u16) Cover {
        return self.tileAt(x, y).cover;
    }

    pub fn regionAt(self: *const World, x: u16, y: u16) Region {
        return self.tileAt(x, y).region;
    }

    pub fn regionInfoAt(self: *const World, x: u16, y: u16) RegionInfo {
        return regionInfo(self.regionAt(x, y));
    }

    fn generate(self: *World) void {
        self.populateBaseTiles();
        self.applyRivers();
        self.applyWetlandPass();
        self.ensureRoutes();
        self.spawn = self.findSpawn();
        self.objective = self.findObjective();
    }

    fn populateBaseTiles(self: *World) void {
        for (0..height) |y_idx| {
            const y: u16 = @intCast(y_idx);
            for (0..width) |x_idx| {
                const x: u16 = @intCast(x_idx);
                const region = selectRegion(self.seed, x, y);
                const config = configForRegion(region);
                const climate = sampleClimate(self.seed, config, x, y);

                self.tiles[y_idx][x_idx] = .{
                    .terrain = classifyTerrain(self.seed, config, climate, x, y),
                    .biome = undefined,
                    .cover = undefined,
                    .variation = variationForCoord(self.seed, x, y),
                    .region = region,
                    .elevation = toByte(climate.elevation),
                    .moisture = toByte(climate.moisture),
                };
                self.refreshVisuals(x, y);
            }
        }
    }

    fn applyRivers(self: *World) void {
        var sources: [8]?Coord = [_]?Coord{null} ** 8;
        var scores: [8]f32 = [_]f32{-1.0} ** 8;

        for (2..height - 2) |y_idx| {
            for (2..width - 2) |x_idx| {
                const tile = self.tiles[y_idx][x_idx];
                if (tile.terrain != .hills) continue;
                if (tile.elevation < 176 or tile.moisture < 110) continue;
                if (!isLocalHighPoint(self, @intCast(x_idx), @intCast(y_idx))) continue;

                var score = byteToUnit(tile.elevation) * 0.75 + byteToUnit(tile.moisture) * 0.25;
                if (tile.region == .iron_ridge) score += 0.12;

                const coord: Coord = .{ .x = @intCast(x_idx), .y = @intCast(y_idx) };
                insertRiverSource(&sources, &scores, coord, score);
            }
        }

        for (sources, 0..) |source_opt, index| {
            if (source_opt) |source| {
                const outlet = chooseRiverOutlet(self.seed, source, index);
                self.ensureOutletWater(outlet);
                _ = self.carveRiver(source, outlet);
            }
        }
    }

    fn applyWetlandPass(self: *World) void {
        for (0..height) |y_idx| {
            for (0..width) |x_idx| {
                const coord: Coord = .{ .x = @intCast(x_idx), .y = @intCast(y_idx) };
                var tile = &self.tiles[y_idx][x_idx];

                if (tile.terrain == .water or tile.terrain == .mountain or tile.terrain == .river) continue;

                const wet_neighbors = countAdjacent(self, coord, .water) + countAdjacent(self, coord, .river);
                if (wet_neighbors >= 2 and tile.elevation < 132 and tile.terrain != .ruins) {
                    tile.terrain = .marsh;
                    tile.moisture = @max(tile.moisture, 190);
                    self.refreshVisuals(coord.x, coord.y);
                    continue;
                }

                if (wet_neighbors >= 1 and tile.terrain == .plains and tile.moisture > 150) {
                    tile.terrain = .forest;
                    self.refreshVisuals(coord.x, coord.y);
                }
            }
        }
    }

    fn ensureRoutes(self: *World) void {
        const y = self.findCentralPassageRow();
        var x: usize = 2;
        while (x < width - 2) : (x += 1) {
            var tile = &self.tiles[y][x];
            if (tile.terrain == .water or tile.terrain == .mountain) {
                tile.terrain = if (tile.region == .dusk_road) .ruins else .plains;
                tile.elevation = @min(tile.elevation, 172);
                tile.moisture = @min(tile.moisture, 150);
                self.refreshVisuals(@intCast(x), @intCast(y));
            }
        }
    }

    fn carveRiver(self: *World, source: Coord, outlet: Coord) bool {
        var visited = [_][width]bool{[_]bool{false} ** width} ** height;
        var path: [512]Coord = undefined;
        var len: usize = 0;
        var current = source;

        while (len < path.len) {
            if (visited[@as(usize, current.y)][@as(usize, current.x)]) break;
            visited[@as(usize, current.y)][@as(usize, current.x)] = true;
            path[len] = current;
            len += 1;

            if (current.x == outlet.x and current.y == outlet.y) break;

            const next = chooseRiverStep(self, current, outlet, &visited) orelse break;
            current = next;

            if (self.terrainAt(current.x, current.y) == .water) {
                path[len - 1] = current;
                break;
            }
        }

        if (len < 8) return false;

        for (path[0..len]) |coord| {
            var tile = &self.tiles[@as(usize, coord.y)][@as(usize, coord.x)];
            if (tile.terrain == .water or tile.terrain == .mountain) continue;
            tile.terrain = .river;
            tile.moisture = @max(tile.moisture, 210);
            tile.elevation = @min(tile.elevation, 168);
            self.refreshVisuals(coord.x, coord.y);
        }
        return true;
    }

    fn ensureOutletWater(self: *World, outlet: Coord) void {
        var tile = &self.tiles[@as(usize, outlet.y)][@as(usize, outlet.x)];
        tile.terrain = .water;
        tile.elevation = @min(tile.elevation, 76);
        tile.moisture = @max(tile.moisture, 210);
        self.refreshVisuals(outlet.x, outlet.y);
    }

    fn findSpawn(self: *const World) Coord {
        var best = Coord{ .x = 6, .y = height_u16 / 2 };
        var best_score: i32 = std.math.minInt(i32);

        for (10..height - 10) |y_idx| {
            for (12..width / 3) |x_idx| {
                const coord: Coord = .{ .x = @intCast(x_idx), .y = @intCast(y_idx) };
                const tile = self.tiles[y_idx][x_idx];
                if (!terrainWalkable(tile.terrain)) continue;

                const edge_distance = @min(@min(x_idx, width - 1 - x_idx), @min(y_idx, height - 1 - y_idx));
                var score: i32 = 180 - @as(i32, @intCast(x_idx));
                switch (tile.terrain) {
                    .plains => score += 30,
                    .forest => score += 18,
                    .ruins => score += 22,
                    .hills => score += 8,
                    .marsh, .river => score -= 8,
                    else => {},
                }
                score += @as(i32, @intCast(edge_distance)) * 3;
                score += 6 * countAdjacentWalkable(self, coord);
                score -= 12 * @as(i32, countAdjacent(self, coord, .water));

                if (score > best_score) {
                    best = coord;
                    best_score = score;
                }
            }
        }
        return best;
    }

    fn findObjective(self: *const World) Coord {
        var best = Coord{ .x = width_u16 - 8, .y = height_u16 / 2 };
        var best_score: i32 = std.math.minInt(i32);

        for (10..height - 10) |y_idx| {
            for (width * 2 / 3..width - 12) |x_idx| {
                const coord: Coord = .{ .x = @intCast(x_idx), .y = @intCast(y_idx) };
                const tile = self.tiles[y_idx][x_idx];
                if (!terrainWalkable(tile.terrain)) continue;

                const edge_distance = @min(@min(x_idx, width - 1 - x_idx), @min(y_idx, height - 1 - y_idx));
                var score: i32 = @as(i32, @intCast(x_idx)) * 2;
                if (tile.region == .dusk_road) score += 40;
                switch (tile.terrain) {
                    .ruins => score += 36,
                    .hills => score += 18,
                    .plains => score += 12,
                    .forest => score += 4,
                    .river, .marsh => score -= 8,
                    else => {},
                }
                score += @as(i32, @intCast(edge_distance)) * 2;

                if (score > best_score) {
                    best = coord;
                    best_score = score;
                }
            }
        }
        return best;
    }

    fn findCentralPassageRow(self: *const World) usize {
        var best_row: usize = height / 2;
        var best_score: i32 = std.math.minInt(i32);

        for (height / 4..height * 3 / 4) |y_idx| {
            var row_score: i32 = 0;
            for (0..width) |x_idx| {
                const terrain = self.tiles[y_idx][x_idx].terrain;
                row_score += switch (terrain) {
                    .plains, .ruins => 3,
                    .forest, .hills => 2,
                    .river, .marsh => 1,
                    .water, .mountain => -4,
                };
            }
            if (row_score > best_score) {
                best_score = row_score;
                best_row = y_idx;
            }
        }
        return best_row;
    }

    fn refreshVisuals(self: *World, x: u16, y: u16) void {
        var tile = &self.tiles[@as(usize, y)][@as(usize, x)];
        tile.biome = classifyBiome(tile.region, tile.terrain, tile.elevation, tile.moisture);
        tile.cover = classifyCover(self.seed, tile.biome, tile.terrain, x, y, tile.elevation, tile.moisture);
    }
};

const ClimateSample = struct {
    elevation: f32,
    moisture: f32,
    ridge: f32,
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

fn sampleClimate(seed: u64, config: *const RegionConfig, x: u16, y: u16) ClimateSample {
    const fx = axisUnit(x, width_u16);
    const fy = axisUnit(y, height_u16);
    const warp_x = fx + (fractalNoise(seed ^ 0x9989d3f1bb39f243, fx * 2.2, fy * 2.2, 3, 2.0, 0.5) - 0.5) * 0.18;
    const warp_y = fy + (fractalNoise(seed ^ 0x7b1f7cf8e812d4c1, fx * 2.2, fy * 2.2, 3, 2.0, 0.5) - 0.5) * 0.16;

    const continental = fractalNoise(seed ^ 0x4137ba5dc9185f1f, warp_x * 2.4, warp_y * 2.0, 4, 2.0, 0.52);
    const relief = fractalNoise(seed ^ 0xa2d4d0c5e45c1d77, warp_x * 6.5, warp_y * 6.5, 3, 2.2, 0.55);
    const moisture_base = fractalNoise(seed ^ 0x51f12d6efc2fb6d3, warp_x * 2.5, warp_y * 2.7, 4, 2.0, 0.54);
    const moisture_detail = fractalNoise(seed ^ 0x8cf0e0fb2f50a991, warp_x * 7.8, warp_y * 7.2, 2, 2.0, 0.5);

    const ridge_center = 0.20 + 0.14 * fractalNoise(seed ^ 0xee7cb53129b2b4e7, warp_x * 1.6, 0.0, 3, 2.0, 0.5) + warp_x * 0.34;
    const ridge_distance = @abs(warp_y - ridge_center);
    const ridge_band = clamp01(1.0 - ridge_distance / 0.16);
    const ridge = ridge_band * ridge_band * smoothstep(0.38, 0.92, warp_x);

    const basin = fractalNoise(seed ^ 0x1ac0f1d7e96c4b2d, warp_x * 1.8, warp_y * 1.6, 3, 2.0, 0.5);
    const basin_cut = smoothstep(0.70, 0.98, basin) * 0.22;

    var elevation = 0.14 + continental * 0.50 + relief * 0.14 + config.elevation_bias + ridge * config.ridge_bias - basin_cut;
    var moisture = 0.30 + moisture_base * 0.48 + moisture_detail * 0.12 + config.moisture_bias;

    if (ridge > 0.32) moisture -= ridge * 0.10;

    elevation = clamp01(elevation);
    moisture = clamp01(moisture);

    return .{
        .elevation = elevation,
        .moisture = moisture,
        .ridge = ridge,
    };
}

fn classifyTerrain(seed: u64, config: *const RegionConfig, climate: ClimateSample, x: u16, y: u16) Terrain {
    const region_index: f32 = @floatFromInt(@intFromEnum(config.region));
    const ruin_noise = fractalNoise(seed ^ 0xd93b4f5a8b1f9c73, axisUnit(x, width_u16) * 8.0 + region_index, axisUnit(y, height_u16) * 8.0 - region_index, 2, 2.0, 0.5);

    if (climate.elevation < 0.31) return .water;
    if (climate.elevation > 0.80 or climate.ridge > 0.82) return .mountain;
    if (climate.elevation > 0.66 or climate.ridge > 0.52) return .hills;
    if (climate.moisture > 0.73 and climate.elevation < 0.47) return .marsh;
    if (climate.moisture > 0.61 + config.forest_threshold_offset and climate.elevation < 0.72) return .forest;
    if (ruin_noise > 0.86 - config.ruin_bonus and climate.elevation > 0.38 and climate.elevation < 0.67) return .ruins;
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

fn classifyCover(seed: u64, biome: Biome, terrain: Terrain, x: u16, y: u16, elevation: u8, moisture: u8) Cover {
    const detail = variationForCoord(seed ^ 0x91f24563dd8c27a1, x, y);
    const elevation_unit = byteToUnit(elevation);
    const moisture_unit = byteToUnit(moisture);

    return switch (terrain) {
        .water => .deep_water,
        .river => .current,
        .marsh => if (detail < 160) .reeds else .current,
        .mountain => if (detail < 180) .stones else .bare,
        .ruins => if (detail < 150) .rubble else .stones,
        .hills => switch (biome) {
            .alpine => if (detail < 170) .stones else .bare,
            .highlands => if (detail < 96) .short_grass else if (detail < 176) .stones else .scrub,
            else => if (detail < 128) .short_grass else .scrub,
        },
        .forest => switch (biome) {
            .deep_forest => if (detail < 208) .tree else .scrub,
            .floodplain => if (detail < 144) .tree else .reeds,
            else => if (detail < 176) .tree else if (detail < 220) .tall_grass else .scrub,
        },
        .plains => switch (biome) {
            .meadow => if (detail < 80) .short_grass else if (detail < 150) .tall_grass else if (detail < 190 and moisture_unit > 0.40) .flowers else .scrub,
            .steppe => if (detail < 96) .short_grass else if (detail < 210) .scrub else .bare,
            .floodplain => if (detail < 120) .tall_grass else if (detail < 205) .reeds else .flowers,
            .rocky_lowlands => if (detail < 90) .short_grass else if (detail < 180 or elevation_unit > 0.60) .stones else .scrub,
            .grove => if (detail < 104) .short_grass else if (detail < 168) .tall_grass else if (detail < 216) .tree else .flowers,
            else => if (detail < 128) .short_grass else .scrub,
        },
    };
}

fn selectRegion(seed: u64, x: u16, y: u16) Region {
    const fx = axisUnit(x, width_u16);
    const fy = axisUnit(y, height_u16);
    const warped_x = @as(f32, @floatFromInt(x)) + (fractalNoise(seed ^ 0x4b2a193df6ea10c5, fx * 2.0, fy * 2.0, 3, 2.0, 0.5) - 0.5) * 14.0;
    const warped_y = @as(f32, @floatFromInt(y)) + (fractalNoise(seed ^ 0x2de9a95cd4f1b73f, fx * 2.0, fy * 2.0, 3, 2.0, 0.5) - 0.5) * 11.0;

    var best = region_configs[0].region;
    var best_score = std.math.inf(f32);

    for (region_configs, 0..) |config, index| {
        const dx = warped_x - @as(f32, @floatFromInt(config.anchor.x));
        const dy = warped_y - @as(f32, @floatFromInt(config.anchor.y));
        const distortion = (fractalNoise(seed +% (@as(u64, index + 1) *% 0x9e3779b97f4a7c15), fx * 4.5, fy * 4.5, 2, 2.0, 0.5) - 0.5) * 36.0;
        const score = dx * dx + dy * dy + distortion;

        if (score < best_score) {
            best_score = score;
            best = config.region;
        }
    }

    return best;
}

fn chooseRiverOutlet(seed: u64, source: Coord, river_index: usize) Coord {
    const jitter = hash01(seed +% (@as(u64, river_index) + 1) *% 0x5851f42d4c957f2d, source.x, source.y);
    const vertical: i32 = if (jitter < 0.5) 1 else -1;
    const drift = @as(i32, @intFromFloat((jitter - 0.5) * 18.0));

    if (source.x > width_u16 / 2) {
        return .{
            .x = width_u16 - 1,
            .y = clampCoord(source.y, vertical * 6 + drift, height_u16),
        };
    }
    if (source.y > height_u16 / 2) {
        return .{
            .x = clampCoord(source.x, drift, width_u16),
            .y = height_u16 - 1,
        };
    }
    return .{
        .x = 0,
        .y = clampCoord(source.y, vertical * 5 + drift, height_u16),
    };
}

fn chooseRiverStep(self: *const World, current: Coord, outlet: Coord, visited: *const [height][width]bool) ?Coord {
    const current_elevation = byteToUnit(self.tileAt(current.x, current.y).elevation);

    var best: ?Coord = null;
    var best_score = std.math.inf(f32);

    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;

            const nx_i = @as(i32, current.x) + dx;
            const ny_i = @as(i32, current.y) + dy;
            if (nx_i < 0 or ny_i < 0 or nx_i >= width_u16 or ny_i >= height_u16) continue;

            const nx: u16 = @intCast(nx_i);
            const ny: u16 = @intCast(ny_i);
            if (visited[@as(usize, ny)][@as(usize, nx)]) continue;

            const coord: Coord = .{ .x = nx, .y = ny };
            const tile = self.tileAt(nx, ny);
            if (tile.terrain == .water) return coord;
            if (tile.terrain == .mountain) continue;

            const elevation = byteToUnit(tile.elevation);
            const distance = normalizedDistance(coord, outlet);
            var score = elevation * 1.15 + distance * 0.75;

            if (elevation > current_elevation) {
                score += (elevation - current_elevation) * 2.6;
            } else {
                score -= @min(0.12, (current_elevation - elevation) * 0.9);
            }

            if (tile.terrain == .marsh or tile.terrain == .river) score -= 0.08;
            if (tile.terrain == .ruins) score += 0.03;

            if (score < best_score) {
                best_score = score;
                best = coord;
            }
        }
    }

    return best;
}

fn insertRiverSource(sources: *[8]?Coord, scores: *[8]f32, coord: Coord, score: f32) void {
    for (sources.*) |existing_opt| {
        if (existing_opt) |existing| {
            if (manhattan(coord, existing) < 24) return;
        }
    }

    var target: ?usize = null;
    var lowest_score = score;
    for (scores.*, 0..) |existing_score, index| {
        if (existing_score < lowest_score) {
            lowest_score = existing_score;
            target = index;
        }
    }

    if (target) |index| {
        sources[index] = coord;
        scores[index] = score;
    }
}

fn countAdjacent(self: *const World, coord: Coord, terrain: Terrain) u8 {
    var count: u8 = 0;
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;

            const nx = @as(i32, coord.x) + dx;
            const ny = @as(i32, coord.y) + dy;
            if (nx < 0 or ny < 0 or nx >= width_u16 or ny >= height_u16) continue;

            if (self.terrainAt(@intCast(nx), @intCast(ny)) == terrain) count += 1;
        }
    }
    return count;
}

fn countAdjacentWalkable(self: *const World, coord: Coord) u8 {
    var count: u8 = 0;
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;

            const nx = @as(i32, coord.x) + dx;
            const ny = @as(i32, coord.y) + dy;
            if (nx < 0 or ny < 0 or nx >= width_u16 or ny >= height_u16) continue;

            if (terrainWalkable(self.terrainAt(@intCast(nx), @intCast(ny)))) count += 1;
        }
    }
    return count;
}

fn isLocalHighPoint(self: *const World, x: u16, y: u16) bool {
    const center = self.tileAt(x, y).elevation;
    var dy: i32 = -1;
    while (dy <= 1) : (dy += 1) {
        var dx: i32 = -1;
        while (dx <= 1) : (dx += 1) {
            if (dx == 0 and dy == 0) continue;

            const nx = @as(i32, x) + dx;
            const ny = @as(i32, y) + dy;
            if (nx < 0 or ny < 0 or nx >= width_u16 or ny >= height_u16) continue;

            if (self.tileAt(@intCast(nx), @intCast(ny)).elevation > center) return false;
        }
    }
    return true;
}

fn manhattan(a: Coord, b: Coord) u16 {
    const dx = if (a.x > b.x) a.x - b.x else b.x - a.x;
    const dy = if (a.y > b.y) a.y - b.y else b.y - a.y;
    return dx + dy;
}

fn normalizedDistance(a: Coord, b: Coord) f32 {
    const dx = @as(f32, @floatFromInt(@abs(@as(i32, a.x) - @as(i32, b.x))));
    const dy = @as(f32, @floatFromInt(@abs(@as(i32, a.y) - @as(i32, b.y))));
    const world_dx = @as(f32, @floatFromInt(width_u16));
    const world_dy = @as(f32, @floatFromInt(height_u16));
    const diagonal = std.math.sqrt(world_dx * world_dx + world_dy * world_dy);
    return std.math.sqrt(dx * dx + dy * dy) / diagonal;
}

fn axisUnit(value: u16, max_value: u16) f32 {
    if (max_value <= 1) return 0.0;
    return @as(f32, @floatFromInt(value)) / @as(f32, @floatFromInt(max_value - 1));
}

fn clampCoord(value: u16, delta: i32, max_exclusive: u16) u16 {
    const shifted = @as(i32, value) + delta;
    if (shifted <= 0) return 0;
    if (shifted >= max_exclusive - 1) return max_exclusive - 1;
    return @intCast(shifted);
}

fn variationForCoord(seed: u64, x: u16, y: u16) u8 {
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

test "world generation is deterministic and feature-rich" {
    const first = World.init(default_seed);
    const second = World.init(default_seed);

    try std.testing.expectEqualDeep(first.tiles, second.tiles);
    try std.testing.expectEqual(first.spawn, second.spawn);

    var water: usize = 0;
    var forest: usize = 0;
    var river: usize = 0;
    var mountain: usize = 0;

    for (first.tiles) |row| {
        for (row) |tile| {
            switch (tile.terrain) {
                .water => water += 1,
                .forest => forest += 1,
                .river => river += 1,
                .mountain => mountain += 1,
                else => {},
            }
        }
    }

    const total_tiles = width * height;

    try std.testing.expect(water > total_tiles / 30);
    try std.testing.expect(forest > total_tiles / 18);
    try std.testing.expect(river > total_tiles / 250);
    try std.testing.expect(mountain > total_tiles / 60);
    try std.testing.expect(terrainWalkable(first.terrainAt(first.spawn.x, first.spawn.y)));
    try std.testing.expect(first.objective.x > first.spawn.x);
}
