const std = @import("std");
const content = @import("content.zig");
const world = @import("world.zig");

const Coord = world.Coord;

pub const InventoryEntry = struct {
    kind: content.ItemKind,
    count: u8 = 1,
};

pub const FeatureState = struct {
    kind: content.FeatureKind,
    depleted: bool = false,
};

pub const WorldObjects = struct {
    allocator: std.mem.Allocator,
    ground_items: std.AutoHashMap(Coord, InventoryEntry),
    features: std.AutoHashMap(Coord, FeatureState),

    pub fn init(allocator: std.mem.Allocator) WorldObjects {
        return .{
            .allocator = allocator,
            .ground_items = std.AutoHashMap(Coord, InventoryEntry).init(allocator),
            .features = std.AutoHashMap(Coord, FeatureState).init(allocator),
        };
    }

    pub fn deinit(self: *WorldObjects) void {
        self.ground_items.deinit();
        self.features.deinit();
    }

    pub fn groundItemAt(self: *const WorldObjects, coord: Coord) ?InventoryEntry {
        return self.ground_items.get(coord);
    }

    pub fn featureAt(self: *const WorldObjects, coord: Coord) ?FeatureState {
        return self.features.get(coord);
    }

    pub fn featurePtr(self: *WorldObjects, coord: Coord) ?*FeatureState {
        return self.features.getPtr(coord);
    }

    pub fn putGroundItem(self: *WorldObjects, coord: Coord, item: InventoryEntry) !void {
        if (self.ground_items.getPtr(coord)) |existing| {
            if (existing.kind == item.kind and content.itemDef(item.kind).stackable) {
                existing.count +|= item.count;
                return;
            }
        }
        try self.ground_items.put(coord, item);
    }

    pub fn takeGroundItem(self: *WorldObjects, coord: Coord) ?InventoryEntry {
        if (self.ground_items.fetchRemove(coord)) |entry| {
            return entry.value;
        }
        return null;
    }

    pub fn putFeature(self: *WorldObjects, coord: Coord, feature: FeatureState) !void {
        try self.features.put(coord, feature);
    }
};
