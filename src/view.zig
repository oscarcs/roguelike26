const std = @import("std");
const game = @import("game.zig");

const line_buf_len = 128;

pub const TextLine = struct {
    buf: [line_buf_len]u8 = [_]u8{0} ** line_buf_len,
    len: usize = 0,

    pub fn slice(self: *const TextLine) []const u8 {
        return self.buf[0..self.len];
    }
};

pub const Summary = struct {
    hp: TextLine = .{},
    stamina: TextLine = .{},
    level: TextLine = .{},
    gold: TextLine = .{},
    turn: TextLine = .{},
    coords: TextLine = .{},
    current_tile: TextLine = .{},
    current_detail: TextLine = .{},
    site: TextLine = .{},
    ground: TextLine = .{},
    objective: TextLine = .{},
    command_hint: []const u8 = "",
    command_placeholder: []const u8 = "",
    inventory_lines: [game.inventory_capacity]TextLine = [_]TextLine{.{}} ** game.inventory_capacity,
    inventory_len: usize = 0,
};

pub const Presentation = struct {
    state: *game.Game,
    summary: *const Summary,
};

pub const Cache = struct {
    summary: Summary = .{},

    pub fn present(self: *Cache, state: *game.Game) Presentation {
        buildInto(&self.summary, state);
        return .{
            .state = state,
            .summary = &self.summary,
        };
    }
};

pub fn buildInto(summary: *Summary, state: *game.Game) void {
    summary.* = Summary{};

    summary.hp.len = fmt(&summary.hp, "{d}/{d}", .{ state.hp, game.max_hp });
    summary.stamina.len = fmt(&summary.stamina, "{d}/{d}", .{ state.stamina, game.max_stamina });
    summary.level.len = fmt(&summary.level, "{d}", .{state.level});
    summary.gold.len = fmt(&summary.gold, "{d}", .{state.gold});
    summary.turn.len = fmt(&summary.turn, "{d}", .{state.turn});
    summary.coords.len = fmt(&summary.coords, "{d},{d}", .{ state.player_x, state.player_y });
    summary.current_tile.len = fmt(&summary.current_tile, "{s}", .{
        game.terrainName(state.currentTerrain()),
    });
    summary.current_detail.len = fmt(&summary.current_detail, "{s} / {s}", .{
        game.biomeName(state.currentBiome()),
        game.coverName(state.currentCover()),
    });

    if (state.featureAt(state.player_x, state.player_y)) |feature| {
        const def = game.featureDefinition(feature.kind);
        if (feature.depleted and def.single_use) {
            summary.site.len = fmt(&summary.site, "{s} (spent)", .{def.name});
        } else {
            summary.site.len = fmt(&summary.site, "{s}: {s}", .{ def.name, def.interaction_hint });
        }
    }

    if (state.groundItemAt(state.player_x, state.player_y)) |item| {
        const def = game.itemDefinition(item.kind);
        if (item.count > 1) {
            summary.ground.len = fmt(&summary.ground, "Ground: {s} x{d}", .{ def.name, item.count });
        } else {
            summary.ground.len = fmt(&summary.ground, "Ground: {s}", .{def.name});
        }
    }

    summary.objective.len = fmt(&summary.objective, "Reach the Watcher's Spire near {d},{d}.", .{
        state.objectiveCoord().x,
        state.objectiveCoord().y,
    });

    summary.command_hint = if (state.command_mode)
        "Enter submits. Esc cancels."
    else
        "g picks up, e interacts, : opens commands.";
    summary.command_placeholder = "look / rest / pickup / interact / use 4";

    summary.inventory_len = state.inventoryCount();
    var i: usize = 0;
    while (i < summary.inventory_len) : (i += 1) {
        const entry = state.inventoryItem(i);
        const def = game.itemDefinition(entry.kind);
        const usable = switch (def.effect) {
            .none => false,
            else => true,
        };

        if (entry.count > 1 and usable) {
            summary.inventory_lines[i].len = fmt(&summary.inventory_lines[i], "{d}. {s} x{d} [use]", .{
                i + 1,
                def.name,
                entry.count,
            });
        } else if (entry.count > 1) {
            summary.inventory_lines[i].len = fmt(&summary.inventory_lines[i], "{d}. {s} x{d}", .{
                i + 1,
                def.name,
                entry.count,
            });
        } else if (usable) {
            summary.inventory_lines[i].len = fmt(&summary.inventory_lines[i], "{d}. {s} [use]", .{
                i + 1,
                def.name,
            });
        } else {
            summary.inventory_lines[i].len = fmt(&summary.inventory_lines[i], "{d}. {s}", .{
                i + 1,
                def.name,
            });
        }
    }
}

fn fmt(line: *TextLine, comptime format: []const u8, args: anytype) usize {
    return (std.fmt.bufPrint(&line.buf, format, args) catch unreachable).len;
}

test "inventory summary formats starter kit entries" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer _ = gpa.deinit();

    var state = try game.Game.init(gpa.allocator());
    defer state.deinit();

    var cache = Cache{};
    const presentation = cache.present(&state);

    try std.testing.expectEqual(@as(usize, 6), presentation.summary.inventory_len);
    try std.testing.expectEqualStrings("1. Iron sword", presentation.summary.inventory_lines[0].slice());
    try std.testing.expectEqualStrings("4. Bandage roll [use]", presentation.summary.inventory_lines[3].slice());
    try std.testing.expectEqualStrings("6. Amber vial [use]", presentation.summary.inventory_lines[5].slice());
}
