pub const ItemKind = enum(u8) {
    iron_sword,
    weather_cloak,
    flint_and_steel,
    bandage_roll,
    old_map_fragment,
    amber_vial,
    trail_rations,
    marsh_salve,
    scavenged_relic,
};

pub const FeatureKind = enum(u8) {
    campfire,
    berry_bush,
    supply_cache,
    waystone,
};

pub const ItemEffect = union(enum) {
    none,
    restore: struct {
        hp: u16 = 0,
        stamina: u16 = 0,
    },
};

pub const ItemDef = struct {
    name: []const u8,
    description: []const u8,
    glyph: []const u8,
    stackable: bool,
    consumed_on_use: bool,
    effect: ItemEffect,
};

pub const FeatureDef = struct {
    name: []const u8,
    description: []const u8,
    glyph: []const u8,
    interaction_hint: []const u8,
    single_use: bool,
};

pub fn itemDef(kind: ItemKind) ItemDef {
    return switch (kind) {
        .iron_sword => .{
            .name = "Iron sword",
            .description = "A practical sidearm with enough weight to feel reassuring on the road.",
            .glyph = "/",
            .stackable = false,
            .consumed_on_use = false,
            .effect = .none,
        },
        .weather_cloak => .{
            .name = "Weather cloak",
            .description = "A patched cloak that keeps the worst of the rain and grit off your shoulders.",
            .glyph = "[",
            .stackable = false,
            .consumed_on_use = false,
            .effect = .none,
        },
        .flint_and_steel => .{
            .name = "Flint and steel",
            .description = "Useful camp kit, though it is more promise than power without dry tinder.",
            .glyph = "!",
            .stackable = false,
            .consumed_on_use = false,
            .effect = .none,
        },
        .bandage_roll => .{
            .name = "Bandage roll",
            .description = "A tightly wrapped field dressing that closes cuts and steadies your breathing.",
            .glyph = "+",
            .stackable = true,
            .consumed_on_use = true,
            .effect = .{ .restore = .{ .hp = 6, .stamina = 1 } },
        },
        .old_map_fragment => .{
            .name = "Old map fragment",
            .description = "A brittle scrap showing faded road marks and a tower silhouette.",
            .glyph = "?",
            .stackable = false,
            .consumed_on_use = false,
            .effect = .none,
        },
        .amber_vial => .{
            .name = "Amber vial",
            .description = "A bitter tonic that puts strength back in your legs for a while.",
            .glyph = "!",
            .stackable = true,
            .consumed_on_use = true,
            .effect = .{ .restore = .{ .hp = 0, .stamina = 5 } },
        },
        .trail_rations => .{
            .name = "Trail rations",
            .description = "Salted meat and hard bread packed for a hungry march.",
            .glyph = "%",
            .stackable = true,
            .consumed_on_use = true,
            .effect = .{ .restore = .{ .hp = 2, .stamina = 4 } },
        },
        .marsh_salve => .{
            .name = "Marsh salve",
            .description = "A reed-scented poultice that cools stings and soothes tired muscles.",
            .glyph = "!",
            .stackable = true,
            .consumed_on_use = true,
            .effect = .{ .restore = .{ .hp = 4, .stamina = 2 } },
        },
        .scavenged_relic => .{
            .name = "Scavenged relic",
            .description = "A worked metal token worth keeping until you find the right buyer.",
            .glyph = "*",
            .stackable = false,
            .consumed_on_use = false,
            .effect = .none,
        },
    };
}

pub fn featureDef(kind: FeatureKind) FeatureDef {
    return switch (kind) {
        .campfire => .{
            .name = "Campfire",
            .description = "A low, steady fire ringed with stones and the remains of an old watch post.",
            .glyph = "*",
            .interaction_hint = "Warm yourself and regroup.",
            .single_use = false,
        },
        .berry_bush => .{
            .name = "Berry bush",
            .description = "Dark leaves hide a few tart berries that travelers can still make use of.",
            .glyph = "&",
            .interaction_hint = "Forage what remains.",
            .single_use = true,
        },
        .supply_cache => .{
            .name = "Supply cache",
            .description = "A weathered crate tucked under canvas, the sort scouts leave for late arrivals.",
            .glyph = "C",
            .interaction_hint = "Search the cache.",
            .single_use = true,
        },
        .waystone => .{
            .name = "Waystone",
            .description = "An old carved marker whose grooves still point the road toward the spire.",
            .glyph = "|",
            .interaction_hint = "Study the marker.",
            .single_use = false,
        },
    };
}
