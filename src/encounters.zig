const world = @import("world.zig");

pub const max_encounters = 48;

pub const Kind = enum(u8) {
    scavenger,
    survey_drone,
    patrol_light,
    vault_guardian,
};

pub const Encounter = struct {
    kind: Kind,
    coord: world.Coord,
    hp: i16,
    wake_turn: u32 = 0,
};

pub fn name(kind: Kind) []const u8 {
    return switch (kind) {
        .scavenger => "Scavenger",
        .survey_drone => "Survey drone",
        .patrol_light => "Patrol light",
        .vault_guardian => "Vault guardian",
    };
}

pub fn glyph(kind: Kind) []const u8 {
    return switch (kind) {
        .scavenger => "s",
        .survey_drone => "m",
        .patrol_light => "*",
        .vault_guardian => "G",
    };
}

pub fn maxHp(kind: Kind) i16 {
    return switch (kind) {
        .scavenger => 5,
        .survey_drone => 4,
        .patrol_light => 3,
        .vault_guardian => 8,
    };
}

pub fn distanceSquared(a: world.Coord, b: world.Coord) i32 {
    const dx = a.x - b.x;
    const dy = a.y - b.y;
    return dx * dx + dy * dy;
}

pub fn signum(value: i32) i32 {
    if (value < 0) return -1;
    if (value > 0) return 1;
    return 0;
}
