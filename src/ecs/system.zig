const std = @import("std");
const sg = @import("sokol").gfx;

const et = @import("entity.zig");
const Entity = et.Entity;
const Archetype = et.Archetype;
const ArchetypeSignature = et.ArchetypeSignature;
const EntityBundle = et.EntityBundle;
const EntityError = et.EntityError;

const RenderContext = @import("root.zig").RenderContext;
const comp = @import("components.zig");
const ComponentId = comp.ComponentId;
const Renderable = comp.Renderable;
const util = @import("../util.zig");
const InitBundle = util.InitBundle;

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
        views: [render_ctxs.len]sg.View = undefined,
        init_bundle: [render_ctxs.len]InitBundle = undefined,

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
                self.views[i] = ctx.get_view_fn_ptr(alloc);
                self.init_bundle[i] = ctx.get_init_bundle_fn_ptr() catch @panic("Failure when initializing bundle");
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

            for (arch.entities.items, 0..) |entity, idx| {
                const location = EntityLocation{ .archetype = &self.archetypes[self.arch_idx], .idx = idx };
                try self.entity_locations.put(entity, location);
            }

            self.arch_idx += 1;
        }

        /// Add a component to a particular entity.
        /// With the current system, this means the following:
        /// - Query the entity
        /// - Take the entity and get all of the columns
        /// - Create a tuple struct for components
        /// - Look through all the archetypes and find a match. If there wasn't one
        ///   create it. We can't dynamically construct types in runtime, so we
        ///   would have to regenerate all of them during comptime
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
                const incoming_id = ComponentId(ComponentType);
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
                for (&self.archetypes) |*arch| {
                    // We found an existing archetype with the same signature
                    if (arch.signature.matches_absolute(new_ids)) {
                        try arch.addEntityWithBundle(&bundle);
                        var location = self.entity_locations.getPtr(entity) orelse return SystemError.MissingEntityLocation;
                        location.archetype = arch;
                        location.idx = arch.entities_idx - 1;
                        break;
                    }
                } else {
                    // We did not find an existing archetype and therefore we need to create one
                    const arch = try Archetype.initWithEntityBundle(self.alloc, &bundle);
                    self.archetypes[self.arch_idx] = arch;
                    self.arch_idx += 1;

                    var location = self.entity_locations.getPtr(entity) orelse return SystemError.MissingEntityLocation;
                    location.archetype = &self.archetypes[self.arch_idx];
                    location.idx = 0;
                }
            }
        }

        /// This is the function that processes the updates that are results of interactivity
        /// i.e. excluding updates of states that are related to spine c runtime
        pub fn update(self: *Self) SystemError!void {
            _ = self;
        }

        pub fn render(self: *Self) !void {
            // The following need to be done here:
            // - We need to query everything in the database for entites that
            //   has the Renderable component
            // - Sort them based on their rendering order
            // - Loop through the query results and call update and then render
            var query_res = try self.getQueryResult(.{Renderable});
            defer query_res.deinit();

            var render_components: std.ArrayList(*Renderable) = .empty;
            defer render_components.deinit(self.alloc);

            while (query_res.next()) |arch| {
                const maybe_comps = arch.getColumn(Renderable);
                if (maybe_comps) |comps| {
                    for (comps) |*renderable| {
                        try render_components.append(self.alloc, renderable);
                    }
                }
            }

            std.mem.sort(*Renderable, render_components.items, {}, struct {
                fn lessThan(context: void, a: *Renderable, b: *Renderable) bool {
                    _ = context;
                    // Here we are assuming everything that's renderable has a skeleton
                    // In the future, if we need to render things that are not related
                    // spine-c we would need to abstract this
                    return a.skeleton.y < b.skeleton.y;
                }
            }.lessThan);

            for (render_components.items) |renderable| {
                const idx = renderable.world_level_id;
                util.updateComponent(renderable);
                util.renderComponent(renderable.*, self.pips[idx], self.samplers[idx], self.views[idx]);
            }
        }

        /// The ComponentTuple here is always contained in an tuple
        pub fn getQueryResult(self: *Self, comptime ComponentTuple: anytype) !QueryResult {
            const component_ids = comptime ids: {
                const info = @typeInfo(@TypeOf(ComponentTuple));
                if (info != .@"struct") @compileError("Component tuple needs to be a struct");

                const fields = info.@"struct".fields;
                // because this is in comptime scope we don't really need to heap allocate this
                var field_ids: [fields.len]u32 = undefined;
                for (fields, 0..) |field, i| {
                    const field_type = @field(ComponentTuple, field.name);
                    field_ids[i] = ComponentId(field_type);
                }
                std.mem.sort(u32, &field_ids, {}, std.sort.asc(u32));

                break :ids field_ids;
            };

            var matching_arches = std.ArrayList(*Archetype).empty;

            for (0..self.arch_idx) |i| {
                var arch = &self.archetypes[i];
                if (arch.signature.matches_absolute(&component_ids)) {
                    try matching_arches.append(self.alloc, arch);
                }
            }

            return .{
                .archetypes = try matching_arches.toOwnedSlice(self.alloc),
                .alloc = self.alloc,
            };
        }
    };
}

/// This is just an iterator for *Archetype
pub const QueryResult = struct {
    const Self = @This();

    archetypes: []*Archetype,
    alloc: std.mem.Allocator,
    cur_idx: usize = 0,

    pub fn deinit(self: Self) void {
        self.alloc.free(self.archetypes);
    }

    pub fn next(self: *Self) ?*Archetype {
        if (self.cur_idx < self.archetypes.len) {
            const to_return = self.archetypes[self.cur_idx];
            self.cur_idx += 1;

            return to_return;
        }

        return null;
    }
};
