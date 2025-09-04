const std = @import("std");
const assert = std.debug.assert;

const ComponentId = @import("components.zig").ComponentId;

pub const Entity = u32;
pub const ComponentsMap = std.HashMap(u32, std.ArrayList(u8), std.hash_map.AutoContext(Entity), 80);

pub const EntityError = error{} || std.mem.Allocator.Error;

pub const Archetype = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    signature: ArchetypeSignature,
    components_map: ComponentsMap,
    entities: std.ArrayList(Entity),
    entities_idx: usize = 0,

    pub fn init(alloc: std.mem.Allocator, comptime components: anytype) Self {
        const components_info = @typeInfo(@TypeOf(components));
        assert(components_info == .@"struct");
        const signature = sig: {
            const fields = components_info.@"struct".fields;
            // Even though we stipulate that components have to be comptime known, it is not
            // guaranteed that the compiler would allocate a completely different stack for
            // different inputs of components. Therefore we need to allocate on the heap
            const component_ids = alloc.alloc(u32, fields.len) catch unreachable;
            inline for (fields, 0..) |field, i| {
                const @"type" = @field(components, field.name);
                const id = ComponentId(@"type");
                component_ids[i] = id;
            }

            break :sig ArchetypeSignature{ .component_ids = component_ids };
        };

        return .{
            .alloc = alloc,
            .components_map = ComponentsMap.init(alloc),
            .entities = std.ArrayList(Entity).init(alloc),
            .signature = signature,
        };
    }

    pub fn deinit(self: *Self) void {
        var component_value_iter = self.components_map.valueIterator();
        while (component_value_iter.next()) |bytes| {
            bytes.deinit();
        }

        self.components_map.deinit();
        self.entities.deinit();
        self.signature.deinit(self.alloc);
    }

    pub fn addEntity(self: *Self, entity_id: Entity, comptime components: anytype) EntityError!void {
        // To add an entity, we need to perform the following:
        // 1. destructure each field in the components tuple struct and add the value to their respective storage (in the components_map)
        // 2. insert the entity in its place in entites array
        // 3. increment entity index
        const type_info = @typeInfo(@TypeOf(components));
        comptime {
            if (type_info != .@"struct") @compileError("components must be a struct");
        }

        inline for (type_info.@"struct".fields) |field| {
            const component_id: u32 = ComponentId(field.type);
            const value = @field(components, field.name);
            var entry = try self.components_map.getOrPutValue(component_id, std.ArrayList(u8).init(self.alloc));
            try entry.value_ptr.appendSlice(std.mem.asBytes(&value));
        }

        try self.entities.append(entity_id);
        self.entities_idx += 1;
    }

    pub fn removeEntity(self: *Self, to_remove: Entity) EntityError!void {
        _ = self;
        _ = to_remove;
    }

    pub fn getColumn(self: Self, comptime T: type) ?[]T {
        const component_id = ComponentId(T);
        const components_in_bytes = self.components_map.get(component_id).?;
        const with_alignment_one = std.mem.bytesAsSlice(T, components_in_bytes.items);

        return @alignCast(with_alignment_one);
    }

    pub fn addComponentToEntity(self: *Self, comptime T: type, value: T) EntityError!void {
        _ = self;
        _ = value;
    }
};

pub const ArchetypeSignature = struct {
    const Self = @This();

    component_ids: []const u32,

    pub fn deinit(self: Self, alloc: std.mem.Allocator) void {
        alloc.free(self.component_ids);
    }

    pub fn matches(self: Self, query_components: []const u32) bool {
        if (self.component_ids.len != query_components.len) {
            return false;
        }

        for (0..query_components.len) |i| {
            if (self.component_ids[i] != query_components[i]) {
                return false;
            }
        }

        return true;
    }
};
