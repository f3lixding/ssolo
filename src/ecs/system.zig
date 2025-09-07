const std = @import("std");
const sg = @import("sokol").gfx;

const RenderContext = @import("root.zig").RenderContext;
const Archetype = @import("entity.zig").Archetype;

pub const SystemError = error{
    InitError,
};

/// System in a an ECS is a database that keeps track of entities and caches them by archetypes
/// It also fulfills queries by said archetypes
pub fn System(
    comptime max_archetypes: usize,
    comptime max_entities: usize,
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
        entities: [max_entities]u32 = @splat(0),
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
        pub fn addComponent(
            self: *Self,
            comptime ComponentType: type,
            entity: u32,
            component: *ComponentType,
        ) void {
            _ = self;
            _ = entity;
            _ = component;
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
