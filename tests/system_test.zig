const sg = @import("sokol").gfx;
const spc = @import("../src/util.zig").spine_c;

const std = @import("std");
const alloc = std.testing.allocator;

const ecs = @import("../src/ecs/root.zig");
const Entity = ecs.Entity;
const Archetype = ecs.Archetype;
const AchetypeSignature = ecs.ArchetypeSignature;
const ComponentId = ecs.ComponentId;
const Renderable = @import("../src/ecs/components.zig").Renderable;

const TestComponentOne = struct {
    field_one: u32,
    field_two: u32,
};

const TestComponentTwo = struct {
    field_three: u32,
    field_four: u32,
};

test "system init" {
    _ = ecs.System(10, &[_]ecs.RenderContext{
        .{
            .get_pip_fn_ptr = struct {
                pub fn get_pip() sg.Pipeline {
                    return sg.Pipeline{};
                }
            }.get_pip,
            .get_sampler_fn_ptr = struct {
                pub fn get_sampler() sg.Sampler {
                    return sg.Sampler{};
                }
            }.get_sampler,
        },
    }).init(alloc) catch unreachable;
}

test "system add component" {
    var system = ecs.System(10, &[_]ecs.RenderContext{
        .{
            .get_pip_fn_ptr = struct {
                pub fn get_pip() sg.Pipeline {
                    return sg.Pipeline{};
                }
            }.get_pip,
            .get_sampler_fn_ptr = struct {
                pub fn get_sampler() sg.Sampler {
                    return sg.Sampler{};
                }
            }.get_sampler,
        },
    }).init(alloc) catch unreachable;
    defer system.deinit();

    const component_types = .{TestComponentOne};
    var arch = Archetype.init(alloc, component_types) catch unreachable;
    const comp_one = TestComponentOne{ .field_one = 1, .field_two = 2 };
    arch.addEntity(system.next_entity_id, .{comp_one}) catch unreachable;
    system.next_entity_id += 1;

    system.addArchetype(arch) catch unreachable;

    const comp_two = TestComponentTwo{ .field_three = 3, .field_four = 4 };
    var entities = [_]Entity{system.next_entity_id - 1};
    var components = [_]TestComponentTwo{comp_two};
    system.addComponent(TestComponentTwo, &entities, &components) catch unreachable;

    // now there should be two archetypes, but first one should be empty
    const arch_count = system.arch_idx;
    std.debug.assert(arch_count == 2);

    const first_arch = &system.archetypes[0];
    std.debug.assert(first_arch.entities.items.len == 0);
    var first_arch_comp_map_iter = first_arch.components_map.valueIterator();
    while (first_arch_comp_map_iter.next()) |arr| {
        std.debug.assert(arr.items.len == 0);
    }
    std.debug.assert(first_arch.entities_idx == 0);

    // locations should have also been updated
    const location_one = system.entity_locations.get(0) orelse unreachable;
    const sig_one = location_one.archetype.signature;
    var sig_ground_truth: [2]u32 = undefined;
    sig_ground_truth[0] = ComponentId(TestComponentOne);
    sig_ground_truth[1] = ComponentId(TestComponentTwo);
    std.mem.sort(u32, &sig_ground_truth, {}, std.sort.asc(u32));
    std.debug.assert(!sig_one.matches(&sig_ground_truth));
}

test "system query" {
    var system = ecs.System(10, &[_]ecs.RenderContext{
        .{
            .get_pip_fn_ptr = struct {
                pub fn get_pip() sg.Pipeline {
                    return sg.Pipeline{};
                }
            }.get_pip,
            .get_sampler_fn_ptr = struct {
                pub fn get_sampler() sg.Sampler {
                    return sg.Sampler{};
                }
            }.get_sampler,
        },
    }).init(alloc) catch unreachable;
    defer system.deinit();

    // Set up by inserting into the system components
    const component_types = .{TestComponentOne};
    var arch = Archetype.init(alloc, component_types) catch unreachable;
    const comp_one = TestComponentOne{
        .field_one = 1,
        .field_two = 2,
    };
    arch.addEntity(system.next_entity_id, .{comp_one}) catch unreachable;
    system.next_entity_id += 1;
    system.addArchetype(arch) catch unreachable;

    // query
    var query_result = system.getQueryResult(.{TestComponentOne}) catch unreachable;
    defer query_result.deinit();

    while (query_result.next()) |res| {
        const col = res.getColumn(TestComponentOne);
        std.debug.assert(col != null);
    }

    // Now we add two multiple components and query them all
    system.addComponent(
        TestComponentTwo,
        @constCast(&[_]Entity{0}),
        @constCast(&[_]TestComponentTwo{.{ .field_three = 3, .field_four = 4 }}),
    ) catch unreachable;

    // If we query again but with both components we should be getting the same entity as well
    var combo_query_result = system.getQueryResult(.{ TestComponentOne, TestComponentTwo }) catch unreachable;
    defer combo_query_result.deinit();

    while (combo_query_result.next()) |res| {
        const column_one = res.getColumn(TestComponentOne);
        const column_two = res.getColumn(TestComponentTwo);

        std.debug.assert(column_one != null);
        std.debug.assert(column_two != null);
    }
}
