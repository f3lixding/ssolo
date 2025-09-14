const std = @import("std");
const sg = @import("sokol").gfx;

const et = @import("entity.zig");
const Entity = et.Entity;
const Archetype = et.Archetype;
const ArchetypeSignature = et.ArchetypeSignature;
const EntityBundle = et.EntityBundle;
const EntityError = et.EntityError;

const RenderContext = @import("root.zig").RenderContext;
const CompoentId = @import("components.zig").ComponentId;

pub const SystemError = error{
    InitError,
    MissingEntityLocation,
} || EntityError;

pub const EntityLocation = struct {
    archetype: *Archetype,
    idx: usize,
};
pub const EntityLocationsMap = std.HashMap(
    Entity,
    EntityLocation,
    std.hash_map.AutoContext(Entity),
    80,
);

/// System in a an ECS is a database that keeps track of entities and caches them by archetypes
/// It also fulfills queries by said archetypes
pub fn System(
    comptime max_archetypes: usize,
    comptime render_ctxs: []const RenderContext,
) type {
    return struct {
        const Self = @This();

        // World level resources
        alloc: std.mem.Allocator = undefined,
        pips: [render_ctxs.len]sg.Pipeline = undefined,
        samplers: [render_ctxs.len]sg.Sampler = undefined,

        // Data associated with ECS management
        archetypes: [max_archetypes]Archetype = undefined,
        arch_idx: usize = 0,
        entity_locations: EntityLocationsMap,
        next_entity_id: u32 = 0,

        pub fn init(alloc: std.mem.Allocator) SystemError!Self {
            var self: Self = .{
                .alloc = alloc,
                .entity_locations = EntityLocationsMap.init(alloc),
            };

            inline for (render_ctxs, 0..) |ctx, i| {
                self.pips[i] = ctx.get_pip_fn_ptr();
                self.samplers[i] = ctx.get_sampler_fn_ptr();
            }

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.entity_locations.deinit();

            for (0..self.arch_idx) |i| {
                self.archetypes[i].deinit();
            }
            // TODO: deinit other fields
        }

        // For testing only
        pub fn addArchetype(self: *Self, arch: Archetype) SystemError!void {
            self.archetypes[self.arch_idx] = arch;
            self.arch_idx += 1;

            for (arch.entities.items, 0..) |entity, idx| {
                const location = EntityLocation{ .archetype = &self.archetypes[self.arch_idx], .idx = idx };
                try self.entity_locations.put(entity, location);
            }
        }

        /// Add a component to a particular entity.
        /// With the current system, this means the following:
        /// - Query the entity
        /// - Take the entity and get all of the columns
        /// - Create a tuple struct for components
        /// - Look through all the archetypes and find a match. If there wasn't one
        ///   create it. We can't dynamically construct types in runtime, so we
        ///   would have to pregenerate all of them during comptime
        /// - Insert the entity to archetype obtained from last step
        // TODO: Make this faster (i.e. fewer pointer chasing and allocations)
        pub fn addComponent(
            self: *Self,
            comptime ComponentType: type,
            entities: []Entity,
            components: []ComponentType,
        ) SystemError!void {
            std.debug.assert(entities.len == components.len);

            for (entities, components) |entity, component| {
                const entity_location = self.entity_locations.get(entity) orelse return SystemError.MissingEntityLocation;
                const src_arch = entity_location.archetype;
                const src_sig = &src_arch.signature;
                const incoming_id = CompoentId(ComponentType);
                const new_component_count = src_sig.component_ids.len + 1;

                var new_ids = try self.alloc.alloc(u32, new_component_count);
                defer self.alloc.free(new_ids);

                for (src_sig.component_ids, 0..) |id, i| {
                    new_ids[i] = id;
                }
                new_ids[new_component_count - 1] = incoming_id;

                var bundle = bundle: {
                    var bundle = try src_arch.removeEntity(entity);
                    try bundle.addComponent(component);
                    break :bundle bundle;
                };

                // Retrieve the components (bytes) associated with the entity
                for (self.archetypes) |arch| {
                    // We found an existing archetype with the same signature
                    if (arch.signature.matches(new_ids)) {
                        try arch.addEntityWithBundle(&bundle);
                        break;
                    }
                } else {
                    // We did not find an existing archetype and therefore we need to create one
                    const arch = try Archetype.initWithEntityBundle(self.alloc, &bundle);
                    self.archetypes[self.arch_idx] = arch;
                    self.arch_idx += 1;
                }
            }
        }

        fn query(self: Self) ?[]u32 {
            _ = self;
            return null;
        }

        /// This is the function that processes the updates that are results of interactivity
        /// i.e. excluding updates of states that are related to spine c runtime
        fn update(self: *Self) SystemError!void {
            _ = self;
        }

        fn render(self: Self) !void {
            // The following need to be done here:
            // - We need to query everything in the database for entites that
            //   has the Renderable component
            // - Loop through the query results and call update and then render
            _ = self;
        }
    };
}
