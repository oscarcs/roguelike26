const content = @import("content.zig");
const encounters = @import("encounters.zig");
const objects = @import("objects.zig");
const world = @import("world.zig");

pub const poi_search_radius: i32 = 170;

pub fn featureFor(tile: world.Tile, roll: u8) content.FeatureKind {
    if (tile.terrain == .ruins) {
        return switch (roll % 6) {
            0 => .cracked_archive,
            1 => .collapsed_vault,
            2 => .drone_hulk,
            3 => .relay_dais,
            4 => .static_field,
            else => .prism_obelisk,
        };
    }

    return switch (tile.region) {
        .mistwood => if (roll % 3 == 0) .nanite_bloom else if (tile.terrain == .forest) .fungal_garden else .scavenger_camp,
        .glass_marsh => if (tile.terrain == .marsh or tile.terrain == .river) .coolant_spring else if (roll % 2 == 0) .nanite_bloom else .drone_hulk,
        .iron_ridge => if (tile.terrain == .hills) .prism_obelisk else if (roll % 2 == 0) .drone_hulk else .collapsed_vault,
        .dusk_road => if (roll % 3 == 0) .relay_dais else if (roll % 3 == 1) .sealed_cache else .survey_pylon,
        .ember_fields => if (roll % 3 == 0) .scavenger_camp else if (roll % 3 == 1) .static_field else .sealed_cache,
    };
}

pub fn lootFor(seed: u64, feature: content.FeatureKind, coord: world.Coord) ?objects.InventoryEntry {
    const roll = coordRoll(seed ^ 0x6c6f6f745f726f6c, coord.x, coord.y);
    return switch (feature) {
        .sealed_cache => .{ .kind = if (roll % 2 == 0) .med_gel else .lumen_cell, .count = 1 },
        .scavenger_camp => .{ .kind = if (roll % 2 == 0) .machine_scrap else .nutrient_paste, .count = 1 },
        .drone_hulk => .{ .kind = .machine_scrap, .count = 1 + @as(u8, @intCast(roll % 2)) },
        .coolant_spring => .{ .kind = .reed_antitoxin, .count = 1 },
        .cracked_archive => .{ .kind = .cipher_shard, .count = 1 },
        .prism_obelisk => if (roll % 4 == 0) .{ .kind = .signal_mirror, .count = 1 } else null,
        .static_field => if (roll % 3 == 0) .{ .kind = .phase_spike, .count = 1 } else null,
        .nanite_bloom => .{ .kind = if (roll % 3 == 0) .gravitic_charm else .machine_scrap, .count = 1 },
        .collapsed_vault => .{ .kind = if (roll % 2 == 0) .ruin_key else .cipher_shard, .count = 1 },
        .relay_dais => if (roll % 5 == 0) .{ .kind = .transit_chart, .count = 1 } else null,
        else => null,
    };
}

pub fn encounterKindFor(tile: world.Tile, roll: u8) encounters.Kind {
    if (tile.terrain == .ruins) return if (roll % 2 == 0) .vault_guardian else .survey_drone;
    return switch (tile.region) {
        .glass_marsh => if (roll % 2 == 0) .survey_drone else .patrol_light,
        .dusk_road => if (roll % 3 == 0) .patrol_light else .survey_drone,
        .mistwood => if (roll % 3 == 0) .survey_drone else .scavenger,
        .iron_ridge => if (roll % 2 == 0) .survey_drone else .vault_guardian,
        .ember_fields => if (roll % 2 == 0) .scavenger else .patrol_light,
    };
}

pub fn itemHasTag(kind: content.ItemKind, tag: content.ItemTag) bool {
    for (content.itemDef(kind).tags) |candidate| {
        if (candidate == tag) return true;
    }
    return false;
}

pub fn coordRoll(seed: u64, x: i32, y: i32) u8 {
    return @intCast((mix(seed, x, y) >> 56) & 0xff);
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
