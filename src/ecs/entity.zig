const std = @import("std");
const assert = std.debug.assert;

const ComponentId = @import("components.zig").ComponentId;

pub const Entity = u32;
pub const ComponentsMap = std.HashMap(u32, std.ArrayList(u8), std.hash_map.AutoContext(Entity), 80);
pub const ComponentSizeMap = std.HashMap(u32, usize, std.hash_map.AutoContext(u32), 80);

pub const EntityError = error{
    IncompatibleArchetype,
    EntityNotFound,
    ClobberedComponentId,
} || std.mem.Allocator.Error;

pub const Archetype = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    signature: ArchetypeSignature,
    components_map: ComponentsMap,
    entities: std.ArrayList(Entity),
    entities_idx: usize = 0,
    component_sizes: ComponentSizeMap,

    pub fn initWithComponentIds(alloc: std.mem.Allocator, component_ids: []const u32) EntityError!Self {
        const signature = try ArchetypeSignature.init(alloc, component_ids);

        return .{
            .alloc = alloc,
            .components_map = ComponentsMap.init(alloc),
            .entities = std.ArrayList(Entity).init(alloc),
            .signature = signature,
            .component_sizes = ComponentSizeMap.init(alloc),
        };
    }

    pub fn init(alloc: std.mem.Allocator, components: anytype) EntityError!Self {
        const components_info = @typeInfo(@TypeOf(components));
        assert(components_info == .@"struct");
        var component_sizes = ComponentSizeMap.init(alloc);

        const signature = sig: {
            const fields = components_info.@"struct".fields;
            var component_ids: [fields.len]u32 = undefined;
            inline for (fields, 0..) |field, i| {
                const @"type" = @field(components, field.name);
                const id = ComponentId(@"type");
                // store the component size:
                const gp_res = try component_sizes.getOrPut(id);
                if (gp_res.found_existing) {
                    return error.ClobberedComponentId;
                } else {
                    const val_ptr = gp_res.value_ptr;
                    val_ptr.* = @sizeOf(@"type");
                }

                component_ids[i] = id;
            }
            std.mem.sort(u32, &component_ids, {}, std.sort.asc(u32));

            break :sig try ArchetypeSignature.init(alloc, &component_ids);
        };

        return .{
            .alloc = alloc,
            .components_map = ComponentsMap.init(alloc),
            .entities = std.ArrayList(Entity).init(alloc),
            .signature = signature,
            .component_sizes = component_sizes,
        };
    }

    pub fn deinit(self: *Self) void {
        var component_value_iter = self.components_map.valueIterator();
        while (component_value_iter.next()) |bytes| {
            bytes.deinit();
        }

        self.components_map.deinit();
        self.entities.deinit();
        self.signature.deinit();
        self.component_sizes.deinit();
    }

    pub fn addEntity(self: *Self, entity_id: Entity, components: anytype) EntityError!void {
        // To add an entity, we need to perform the following:
        // 1. destructure each field in the components tuple struct and add the value to their respective storage (in the components_map)
        // 2. insert the entity in its place in entites array
        // 3. increment entity index
        const type_info = @typeInfo(@TypeOf(components));
        if (type_info != .@"struct") @compileError("components must be a struct");
        const fields = type_info.@"struct".fields;
        var component_ids: [fields.len]u32 = undefined;

        inline for (fields, 0..) |field, i| {
            const @"type" = @TypeOf(@field(components, field.name));
            const id = ComponentId(@"type");
            component_ids[i] = id;
        }
        std.mem.sort(u32, &component_ids, {}, std.sort.asc(u32));

        if (!self.signature.matches(&component_ids)) {
            return EntityError.IncompatibleArchetype;
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

    pub fn removeEntity(self: *Self, to_remove: Entity) EntityError!EntityBundle {
        const idx_res = for (self.entities.items, 0..) |id, i| {
            if (id == to_remove) break @as(u32, @intCast(i));
        } else EntityError.EntityNotFound;
        const idx: u32 = try idx_res;

        // Create a sink for the to-be deleted elements
        var sink = try EntityBundle.init(self.alloc, to_remove);
        errdefer sink.deinit();

        // First, cycle through the component map to remove the associated component
        var cm_iter = self.components_map.iterator();
        while (cm_iter.next()) |entry| {
            const component_id = entry.key_ptr.*;
            const components = entry.value_ptr;

            // Get the size of this component type
            const component_size = self.component_sizes.get(component_id) orelse continue;

            // Calculate byte positions for the element to remove and the last element
            const element_to_remove_start = idx * component_size;
            const last_element_idx = self.entities_idx - 1;
            const last_element_start = last_element_idx * component_size;

            // Put the deleted elements in the sink
            const byte_arr = try sink.components.getOrPutValue(component_id, std.ArrayList(u8).init(self.alloc));
            try byte_arr.value_ptr.appendSlice(components.items[element_to_remove_start .. element_to_remove_start + component_size]);

            // Only swap if we're not removing the last element
            if (idx != last_element_idx) {
                // Copy the last element to the position of the element being removed
                const src_slice = components.items[last_element_start .. last_element_start + component_size];
                const dst_slice = components.items[element_to_remove_start .. element_to_remove_start + component_size];
                @memcpy(dst_slice, src_slice);
            }

            // Remove the last element (shrink the array)
            components.shrinkRetainingCapacity(components.items.len - component_size);
        }

        // Second, we need to remove the entity from the list of entities using swap remove
        _ = self.entities.swapRemove(idx);

        // Finally, we decrement the entity_idx
        self.entities_idx -= 1;

        return sink;
    }

    pub fn getColumn(self: Self, comptime T: type) ?[]T {
        const component_id = ComponentId(T);
        const components_in_bytes = self.components_map.get(component_id).?;
        const with_alignment_one = std.mem.bytesAsSlice(T, components_in_bytes.items);

        return @alignCast(with_alignment_one);
    }
};

pub const ArchetypeSignature = struct {
    const Self = @This();

    component_ids: []const u32,
    alloc: std.mem.Allocator = undefined,

    pub fn init(alloc: std.mem.Allocator, component_ids: []const u32) !Self {
        const sorted_ids = try alloc.dupe(u32, component_ids);
        std.mem.sort(u32, sorted_ids, {}, std.sort.asc(u32));
        return .{
            .alloc = alloc,
            .component_ids = sorted_ids,
        };
    }

    pub fn deinit(self: Self) void {
        self.alloc.free(self.component_ids);
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

pub const EntityBundle = struct {
    const Self = @This();

    entity_id: Entity,
    components: ComponentsMap,
    alloc: std.mem.Allocator,

    pub fn init(alloc: std.mem.Allocator, entity_id: Entity) !Self {
        const components = std.HashMap(u32, std.ArrayList(u8), std.hash_map.AutoContext(u32), 80).init(alloc);

        return .{
            .entity_id = entity_id,
            .components = components,
            .alloc = alloc,
        };
    }

    pub fn deinit(self: *Self) void {
        var iter = self.components.valueIterator();

        while (iter.next()) |byte_array| {
            byte_array.deinit();
        }

        self.components.deinit();
    }
};
