const std = @import("std");

const ComponentId = @import("components.zig").ComponentId;

pub const Entity = u32;
pub const ComponentsMap = std.HashMap(Entity, std.ArrayList(u8), std.hash_map.AutoContext(Entity), 80);

pub const EntityError = error{} || std.mem.Allocator.Error;

pub const Archetype = struct {
    const Self = @This();

    alloc: std.mem.Allocator = undefined,
    components_map: ComponentsMap = undefined,
    entities: std.ArrayList(Entity) = undefined,
    entities_idx: usize = 0,

    pub fn init(alloc: std.mem.Allocator) Self {
        return .{
            .alloc = alloc,
            .components_map = ComponentsMap.init(alloc),
            .entities = std.ArrayList(Entity).init(alloc),
        };
    }

    pub fn deinit(self: *Self) void {
        var component_value_iter = self.components_map.valueIterator();
        while (component_value_iter.next()) |bytes| {
            bytes.deinit();
        }

        self.components_map.deinit();
        self.entities.deinit();
    }

    pub fn addEntity(self: *Self, entity_id: Entity, comptime components: anytype) EntityError!void {
        // To add an entity, we need to perform the following:
        // 1. destructure each field in the components tuple struct and add the value to their respective storage (in the components_map)
        // 2. insert the entity in its place in entites array
        // 3. increment entity index
        const type_info = @typeInfo(@TypeOf(components));
        if (type_info != .@"struct") @compileError("components must be a struct");

        inline for (type_info.@"struct".fields) |field| {
            const component_id: u32 = ComponentId(field.type);
            const value = @field(components, field.name);
            if (self.components_map.getPtr(component_id)) |bytes| {
                try bytes.appendSlice(std.mem.asBytes(&value));
            } else {
                var bytes = std.ArrayList(u8).init(self.alloc);
                try bytes.appendSlice(std.mem.asBytes(&value));
                try self.components_map.put(component_id, bytes);
            }
        }

        try self.entities.append(entity_id);
        self.entities_idx += 1;
    }

    pub fn removeEntity(self: *Self, to_remove: Entity) EntityError!void {
        _ = self;
        _ = to_remove;
    }

    pub fn getColumn(self: Self, comptime T: type) ?[]T {
        _ = self;
    }
};

pub const ArchetypeSignature = struct {
    const Self = @This();

    component_ids: []const u32,

    pub fn matches(self: Self, query_components: []const u32) bool {
        return for (query_components) |component_id| res: {
            var found = false;
            for (self.component_ids) |id| {
                if (id == component_id) {
                    found = true;
                    break;
                }
            }
            if (!found) break :res false;
        } else true;
    }
};
