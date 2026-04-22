const std = @import("std");
const vaxis = @import("vaxis");
const game = @import("game.zig");

const minimum_width: u16 = 72;
const minimum_height: u16 = 24;
const inventory_lines = [_][]const u8{
    "1. Iron sword",
    "2. Weather cloak",
    "3. Flint and steel",
    "4. Bandage roll",
    "5. Old map fragment",
    "6. Amber vial",
};

const Rect = struct {
    x: u16,
    y: u16,
    width: u16,
    height: u16,
};

const Layout = struct {
    stats: Rect,
    overworld: Rect,
    minimap: Rect,
    region: Rect,
    world: Rect,
    log: Rect,
    inventory: Rect,
};

pub fn draw(root: vaxis.Window, state: *game.Game) void {
    root.clear();
    root.hideCursor();

    if (root.width < minimum_width or root.height < minimum_height) {
        drawResizeNotice(root);
        return;
    }

    const layout = computeLayout(root);
    drawStatsPanel(root, state, layout.stats);
    drawOverworld(root, state, layout.overworld);
    drawMiniMap(root, state, layout.minimap);
    drawRegionPanel(root, state, layout.region);
    drawWorldPanel(root, state, layout.world);
    drawLogPanel(root, state, layout.log);
    drawInventoryPanel(root, layout.inventory);
}

fn computeLayout(root: vaxis.Window) Layout {
    var top_height = root.height * 3 / 4;
    const minimum_bottom: u16 = 7;
    if (root.height - top_height < minimum_bottom) {
        top_height = root.height - minimum_bottom;
    }

    var left_width = std.math.clamp(root.width * 20 / 100, @as(u16, 18), @as(u16, 32));
    var right_width = std.math.clamp(root.width * 26 / 100, @as(u16, 22), @as(u16, 40));
    const minimum_middle: u16 = 36;

    if (left_width + right_width + minimum_middle > root.width) {
        const side_total = root.width - minimum_middle;
        left_width = side_total * 9 / 20;
        right_width = side_total - left_width;
    }

    const middle_width = root.width - left_width - right_width;
    const bottom_height = root.height - top_height;
    const right_x = left_width + middle_width;

    var minimap_height = std.math.clamp(top_height / 3, @as(u16, 8), @as(u16, 12));
    if (minimap_height + 10 > top_height) {
        minimap_height = top_height / 2;
    }
    const detail_height = top_height - minimap_height;
    const region_height = detail_height / 2;
    const world_height = detail_height - region_height;

    return .{
        .stats = .{ .x = 0, .y = 0, .width = left_width, .height = top_height },
        .overworld = .{ .x = left_width, .y = 0, .width = middle_width, .height = top_height },
        .minimap = .{ .x = right_x, .y = 0, .width = right_width, .height = minimap_height },
        .region = .{ .x = right_x, .y = minimap_height, .width = right_width, .height = region_height },
        .world = .{ .x = right_x, .y = minimap_height + region_height, .width = right_width, .height = world_height },
        .log = .{ .x = 0, .y = top_height, .width = left_width + middle_width, .height = bottom_height },
        .inventory = .{ .x = right_x, .y = top_height, .width = right_width, .height = bottom_height },
    };
}

fn drawResizeNotice(root: vaxis.Window) void {
    const notice = root.child(.{
        .x_off = 2,
        .y_off = 1,
        .width = root.width -| 4,
        .height = root.height -| 2,
        .border = .{
            .where = .all,
            .style = .{ .fg = rgb(0x90, 0xd0, 0xff) },
        },
    });

    _ = notice.printSegment(.{
        .text = "roguelike26 needs a little more room for the full HUD.",
        .style = .{ .fg = rgb(0xf5, 0xe9, 0x8a), .bold = true },
    }, .{ .row_offset = 1, .wrap = .word });
    _ = notice.printSegment(.{
        .text = "Target at least 72 columns by 24 rows.",
        .style = .{ .fg = rgb(0xc7, 0xd1, 0xdc) },
    }, .{ .row_offset = 3, .wrap = .word });
}

fn drawStatsPanel(root: vaxis.Window, state: *const game.Game, rect: Rect) void {
    const panel = makePanel(root, rect, "Character", rgb(0x79, 0xc7, 0xff));

    var line: u16 = 0;
    drawMeter(panel, &line, "HP", state.hpText(), state.hp, game.max_hp, rgb(0xff, 0x8f, 0x8f));
    drawMeter(panel, &line, "ST", state.staminaText(), state.stamina, game.max_stamina, rgb(0x7e, 0xf0, 0xa0));

    line += 1;
    drawValue(panel, &line, "Level", state.levelText());
    drawValue(panel, &line, "Gold", state.goldText());
    drawValue(panel, &line, "Turn", state.turnText());
}

fn drawOverworld(root: vaxis.Window, state: *const game.Game, rect: Rect) void {
    const panel = makePanel(root, rect, "Overworld", rgb(0xf5, 0xe9, 0x8a));
    if (panel.width == 0 or panel.height == 0) return;

    const map_view = panel.child(.{
        .width = panel.width,
        .height = panel.height,
    });

    const start_x = cameraOrigin(state.player_x, map_view.width, game.world_width);
    const start_y = cameraOrigin(state.player_y, map_view.height, game.world_height);
    const visible_width = @min(map_view.width, game.world_width - start_x);
    const visible_height = @min(map_view.height, game.world_height - start_y);

    var row: u16 = 0;
    while (row < visible_height) : (row += 1) {
        const world_y = start_y + row;
        var col: u16 = 0;
        while (col < visible_width) : (col += 1) {
            const world_x = start_x + col;
            const tile = state.tileAt(world_x, world_y);
            map_view.writeCell(col, row, overworldCell(tile));
        }
    }

    const player_col = state.player_x - start_x;
    const player_row = state.player_y - start_y;
    if (player_col < map_view.width and player_row < map_view.height) {
        map_view.writeCell(player_col, player_row, .{
            .char = .{ .grapheme = "@", .width = 1 },
            .style = .{
                .fg = rgb(0x20, 0x1f, 0x18),
                .bg = rgb(0xff, 0x76, 0x6b),
                .bold = true,
            },
        });
    }
}

fn drawMiniMap(root: vaxis.Window, state: *const game.Game, rect: Rect) void {
    const panel = makePanel(root, rect, "Mini Map", rgb(0x79, 0xc7, 0xff));
    if (panel.width == 0 or panel.height == 0) return;

    var row: u16 = 0;
    while (row < panel.height) : (row += 1) {
        const world_y = row * game.world_height / @max(panel.height, 1);
        var col: u16 = 0;
        while (col < panel.width) : (col += 1) {
            const world_x = col * game.world_width / @max(panel.width, 1);
            const terrain = state.terrainAt(world_x, world_y);
            panel.writeCell(col, row, minimapCell(terrain));
        }
    }

    const player_col = state.player_x * panel.width / game.world_width;
    const player_row = state.player_y * panel.height / game.world_height;
    if (player_col < panel.width and player_row < panel.height) {
        panel.writeCell(player_col, player_row, .{
            .char = .{ .grapheme = "@", .width = 1 },
            .style = .{ .fg = rgb(0xff, 0xf7, 0xd1), .bold = true },
        });
    }
}

fn drawRegionPanel(root: vaxis.Window, state: *const game.Game, rect: Rect) void {
    const panel = makePanel(root, rect, "Region", rgb(0x7e, 0xf0, 0xa0));

    _ = panel.printSegment(.{
        .text = game.regionName(state.currentRegion()),
        .style = .{ .fg = rgb(0xf5, 0xe9, 0x8a), .bold = true },
    }, .{ .row_offset = 0, .wrap = .word });

    _ = panel.printSegment(.{
        .text = state.regionSummary(),
        .style = .{ .fg = rgb(0xc7, 0xd1, 0xdc) },
    }, .{ .row_offset = 2, .wrap = .word });

    _ = panel.printSegment(.{
        .text = state.currentLandmark(),
        .style = .{ .fg = rgb(0x79, 0xc7, 0xff) },
    }, .{ .row_offset = 5, .wrap = .word });
}

fn drawWorldPanel(root: vaxis.Window, state: *const game.Game, rect: Rect) void {
    const panel = makePanel(root, rect, "World Info", rgb(0xff, 0xa0, 0x7a));

    _ = panel.printSegment(.{
        .text = "Here",
        .style = .{ .fg = rgb(0xf5, 0xe9, 0x8a), .bold = true },
    }, .{ .row_offset = 0, .wrap = .none });
    _ = panel.printSegment(.{
        .text = state.currentTileText(),
        .style = .{ .fg = rgb(0xc7, 0xd1, 0xdc) },
    }, .{ .row_offset = 1, .wrap = .word });

    _ = panel.printSegment(.{
        .text = state.currentDetailText(),
        .style = .{ .fg = rgb(0xc7, 0xd1, 0xdc) },
    }, .{ .row_offset = 2, .wrap = .word });

    _ = panel.printSegment(.{
        .text = state.coordsText(),
        .style = .{ .fg = rgb(0x88, 0x99, 0xaa) },
    }, .{ .row_offset = 3, .wrap = .none });

    _ = panel.printSegment(.{
        .text = "Goal: reach the spire to the east.",
        .style = .{ .fg = rgb(0xc7, 0xd1, 0xdc) },
    }, .{ .row_offset = 4, .wrap = .word });
}

fn drawLogPanel(root: vaxis.Window, state: *game.Game, rect: Rect) void {
    const panel = makePanel(root, rect, "Message Log", rgb(0x90, 0xd0, 0xff));
    if (panel.width == 0 or panel.height == 0) return;

    const command_height: u16 = if (panel.height > 5) 3 else 2;
    const log_height = panel.height -| command_height;
    const log_view = panel.child(.{ .width = panel.width, .height = log_height });

    const visible = @min(state.logCount(), log_view.height);
    const start = state.logCount() - visible;

    var row: u16 = 0;
    while (row < visible) : (row += 1) {
        _ = log_view.printSegment(.{
            .text = state.logMessage(start + row),
            .style = .{ .fg = rgb(0xc7, 0xd1, 0xdc) },
        }, .{ .row_offset = row, .wrap = .word });
    }

    const command_outer = panel.child(.{
        .y_off = @intCast(log_height),
        .width = panel.width,
        .height = command_height,
        .border = .{
            .where = .top,
            .style = .{ .fg = rgb(0x3f, 0x57, 0x71) },
        },
    });

    _ = command_outer.printSegment(.{
        .text = state.commandHint(),
        .style = .{ .fg = rgb(0x88, 0x99, 0xaa) },
    }, .{ .row_offset = 0, .wrap = .word });

    const prompt = command_outer.child(.{
        .y_off = 1,
        .width = command_outer.width,
        .height = 1,
    });

    prompt.writeCell(0, 0, .{
        .char = .{ .grapheme = ">", .width = 1 },
        .style = .{ .fg = rgb(0xf5, 0xe9, 0x8a), .bold = true },
    });

    const input_view = prompt.child(.{
        .x_off = 2,
        .width = prompt.width -| 2,
        .height = 1,
    });

    if (state.command_mode) {
        state.command_input.drawWithStyle(input_view, .{ .fg = rgb(0xff, 0xf7, 0xd1) });
    } else {
        _ = input_view.printSegment(.{
            .text = "look / rest / where / inventory / clear",
            .style = .{ .fg = rgb(0x5e, 0x6d, 0x7e), .italic = true },
        }, .{ .row_offset = 0, .wrap = .none });
    }
}

fn drawInventoryPanel(root: vaxis.Window, rect: Rect) void {
    const panel = makePanel(root, rect, "Inventory", rgb(0xff, 0xa0, 0x7a));

    var row: u16 = 0;
    for (inventory_lines) |item| {
        if (row >= panel.height) break;
        _ = panel.printSegment(.{
            .text = item,
            .style = .{ .fg = rgb(0xc7, 0xd1, 0xdc) },
        }, .{ .row_offset = row, .wrap = .word });
        row += 1;
    }
}

fn makePanel(root: vaxis.Window, rect: Rect, title: []const u8, border_color: vaxis.Color) vaxis.Window {
    const inner = root.child(.{
        .x_off = @intCast(rect.x),
        .y_off = @intCast(rect.y),
        .width = rect.width,
        .height = rect.height,
        .border = .{
            .where = .all,
            .style = .{ .fg = border_color },
        },
    });

    if (rect.width > 4 and rect.height > 0) {
        const title_win = root.child(.{
            .x_off = @intCast(rect.x + 2),
            .y_off = @intCast(rect.y),
            .width = rect.width -| 4,
            .height = 1,
        });
        _ = title_win.printSegment(.{
            .text = title,
            .style = .{ .fg = border_color, .bold = true, .bg = rgb(0x0f, 0x14, 0x1d) },
        }, .{ .row_offset = 0, .wrap = .none });
    }

    return inner;
}

fn drawMeter(win: vaxis.Window, line: *u16, label: []const u8, value_text: []const u8, value: u16, max_value: u16, color: vaxis.Color) void {
    const label_result = win.printSegment(.{
        .text = label,
        .style = .{ .fg = color, .bold = true },
    }, .{ .row_offset = line.*, .wrap = .none });
    _ = win.printSegment(.{
        .text = " ",
        .style = .{ .fg = color, .bold = true },
    }, .{ .row_offset = line.*, .col_offset = label_result.col, .wrap = .none });
    _ = win.printSegment(.{
        .text = value_text,
        .style = .{ .fg = color, .bold = true },
    }, .{ .row_offset = line.*, .col_offset = label_result.col + 1, .wrap = .none });
    line.* += 1;

    drawMeterBar(win, line.*, value, max_value, color);
    line.* += 1;
}

fn drawValue(win: vaxis.Window, line: *u16, label: []const u8, value: []const u8) void {
    const label_result = win.printSegment(.{
        .text = label,
        .style = .{ .fg = rgb(0xc7, 0xd1, 0xdc) },
    }, .{ .row_offset = line.*, .wrap = .none });
    const colon_result = win.printSegment(.{
        .text = ": ",
        .style = .{ .fg = rgb(0x88, 0x99, 0xaa) },
    }, .{ .row_offset = line.*, .col_offset = label_result.col, .wrap = .none });
    _ = win.printSegment(.{
        .text = value,
        .style = .{ .fg = rgb(0xc7, 0xd1, 0xdc) },
    }, .{ .row_offset = line.*, .col_offset = colon_result.col, .wrap = .none });
    line.* += 1;
}

fn drawMeterBar(win: vaxis.Window, row: u16, value: u16, max_value: u16, color: vaxis.Color) void {
    if (win.width < 3) return;

    const bar_width = @min(@as(u16, 12), win.width -| 2);
    const fill = if (max_value == 0) 0 else @as(u16, @intCast(@as(u32, value) * bar_width / max_value));

    win.writeCell(0, row, .{
        .char = .{ .grapheme = "[", .width = 1 },
        .style = .{ .fg = color },
    });

    var col: u16 = 0;
    while (col < bar_width) : (col += 1) {
        win.writeCell(col + 1, row, .{
            .char = .{ .grapheme = if (col < fill) "#" else "-", .width = 1 },
            .style = .{ .fg = color },
        });
    }

    win.writeCell(bar_width + 1, row, .{
        .char = .{ .grapheme = "]", .width = 1 },
        .style = .{ .fg = color },
    });
}

fn cameraOrigin(player: u16, viewport: u16, world: u16) u16 {
    if (viewport >= world) return 0;

    const half = viewport / 2;
    if (player <= half) return 0;
    if (player + half >= world) return world - viewport;
    return player - half;
}

fn overworldCell(tile: game.Tile) vaxis.Cell {
    return switch (tile.cover) {
        .short_grass => .{
            .char = .{ .grapheme = ".", .width = 1 },
            .style = .{ .fg = coverColor(tile, rgb(0x7e, 0xa4, 0x61), rgb(0x8f, 0xc0, 0x69)) },
        },
        .tall_grass => .{
            .char = .{ .grapheme = "\"", .width = 1 },
            .style = .{ .fg = coverColor(tile, rgb(0x86, 0xad, 0x68), rgb(0x9b, 0xc9, 0x72)) },
        },
        .flowers => .{
            .char = .{ .grapheme = "'", .width = 1 },
            .style = .{ .fg = coverColor(tile, rgb(0xd8, 0xd0, 0x80), rgb(0xf0, 0xe0, 0x95)) },
        },
        .scrub => .{
            .char = .{ .grapheme = ";", .width = 1 },
            .style = .{ .fg = coverColor(tile, rgb(0x6e, 0x8d, 0x54), rgb(0x84, 0xa3, 0x63)) },
        },
        .tree => .{
            .char = .{ .grapheme = "T", .width = 1 },
            .style = .{ .fg = coverColor(tile, rgb(0x4a, 0x7c, 0x4f), rgb(0x5c, 0x93, 0x5f)), .bold = tile.biome == .deep_forest },
        },
        .reeds => .{
            .char = .{ .grapheme = ",", .width = 1 },
            .style = .{ .fg = coverColor(tile, rgb(0x8f, 0xa7, 0x6a), rgb(0xa8, 0xb9, 0x77)) },
        },
        .stones => .{
            .char = .{ .grapheme = ":", .width = 1 },
            .style = .{ .fg = coverColor(tile, rgb(0xb3, 0xa0, 0x8a), rgb(0xc5, 0xb3, 0x9c)) },
        },
        .rubble => .{
            .char = .{ .grapheme = "#", .width = 1 },
            .style = .{ .fg = coverColor(tile, rgb(0xb4, 0xaa, 0x92), rgb(0xcd, 0xc3, 0xaa)) },
        },
        .current => .{
            .char = .{ .grapheme = "=", .width = 1 },
            .style = .{ .fg = coverColor(tile, rgb(0x72, 0xb3, 0xdc), rgb(0x86, 0xc8, 0xee)) },
        },
        .deep_water => .{
            .char = .{ .grapheme = "~", .width = 1 },
            .style = .{ .fg = coverColor(tile, rgb(0x56, 0x88, 0xca), rgb(0x67, 0x9c, 0xe2)) },
        },
        .bare => switch (tile.terrain) {
            .mountain => .{
                .char = .{ .grapheme = "M", .width = 1 },
                .style = .{ .fg = coverColor(tile, rgb(0xa8, 0x9b, 0x90), rgb(0xc0, 0xb2, 0xa5)), .bold = true },
            },
            .hills => .{
                .char = .{ .grapheme = "^", .width = 1 },
                .style = .{ .fg = coverColor(tile, rgb(0xa8, 0x8d, 0x65), rgb(0xc2, 0xa2, 0x74)) },
            },
            else => .{
                .char = .{ .grapheme = "_", .width = 1 },
                .style = .{ .fg = coverColor(tile, rgb(0x91, 0x87, 0x6d), rgb(0xab, 0x9f, 0x80)) },
            },
        },
    };
}

fn minimapCell(terrain: game.Terrain) vaxis.Cell {
    return switch (terrain) {
        .plains => .{
            .char = .{ .grapheme = ".", .width = 1 },
            .style = .{ .fg = rgb(0x5d, 0x78, 0x4f) },
        },
        .forest => .{
            .char = .{ .grapheme = "*", .width = 1 },
            .style = .{ .fg = rgb(0x4d, 0x8a, 0x58) },
        },
        .hills => .{
            .char = .{ .grapheme = "^", .width = 1 },
            .style = .{ .fg = rgb(0xaa, 0x86, 0x53) },
        },
        .marsh => .{
            .char = .{ .grapheme = ",", .width = 1 },
            .style = .{ .fg = rgb(0x81, 0x94, 0x6a) },
        },
        .ruins => .{
            .char = .{ .grapheme = "#", .width = 1 },
            .style = .{ .fg = rgb(0xa6, 0x9d, 0x89) },
        },
        .river => .{
            .char = .{ .grapheme = "=", .width = 1 },
            .style = .{ .fg = rgb(0x68, 0xa6, 0xd8) },
        },
        .water => .{
            .char = .{ .grapheme = "~", .width = 1 },
            .style = .{ .fg = rgb(0x4a, 0x76, 0xb5) },
        },
        .mountain => .{
            .char = .{ .grapheme = "M", .width = 1 },
            .style = .{ .fg = rgb(0x92, 0x86, 0x7a) },
        },
    };
}

fn coverColor(tile: game.Tile, base_a: vaxis.Color, base_b: vaxis.Color) vaxis.Color {
    return if (tile.variation < 128) base_a else base_b;
}

fn rgb(r: u8, g: u8, b: u8) vaxis.Color {
    return .{ .rgb = .{ r, g, b } };
}
