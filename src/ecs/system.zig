const std = @import("std");
const sg = @import("sokol").gfx;
const Entity = @import("entity.zig").Entity;

const RenderContext = @import("root.zig").RenderContext;
const Archetype = @import("entity.zig").Archetype;
const ArchetypeSignature = @import("entity.zig").ArchetypeSignature;
const CompoentId = @import("components.zig").ComponentId;

pub const SystemError = error{
    InitError,
    MissingEntityLocation,
};

pub const EntityLocation = struct {
    archetype: *Archetype,
    idx: usize,
};

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
        entity_locations: std.HashMap(Entity, EntityLocation) = undefined,
        next_entity_id: u32 = 0,

        pub fn init(self: *Self, allocator: std.mem.Allocator) SystemError!void {
            self.alloc = allocator;
            inline for (render_ctxs, 0..) |ctx, i| {
                self.pips[i] = ctx.get_pip_fn_ptr();
                self.samplers[i] = ctx.get_sampler_fn_ptr();
            }
        }

        pub fn createEntity(self: *Self) u32 {
            const current_id = self.next_entity_id;
            self.next_entity_id += 1;
            return current_id;
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
        pub fn addComponent(
            self: *Self,
            comptime ComponentType: type,
            entity: u32,
            component: ComponentType,
        ) SystemError!void {
            const entity_location = self.entity_locations.get(entity) orelse return SystemError.MissingEntityLocation;
            const src_arch = entity_location.archetype;
            // const src_idx = entity_location.idx;
            const src_sig = &src_arch.signature;
            const incoming_id = CompoentId(ComponentType);
            const new_component_count = src_sig.component_ids.len + 1;
            _ = component;

            var new_ids = try self.alloc.alloc(u32, new_component_count);
            defer self.alloc.free(new_ids);

            for (src_sig.component_ids, 0..) |id, i| {
                new_ids[i] = id;
            }
            new_ids[new_component_count - 1] = incoming_id;

            // Retrieve the components (bytes) associated with the entity
            for (self.archetypes) |arch| {
                // We found an existing archetype with the same signature
                if (arch.signature.matches(new_ids)) {
                    break;
                }
            } else {
                // We did not find an existing archetype and therefore we need to create one
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
