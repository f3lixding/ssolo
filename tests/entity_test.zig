const std = @import("std");
const ecs = @import("../src/ecs/root.zig");
const Archetype = ecs.Archetype;
const ArchetypeSignature = ecs.ArchetypeSignature;
const Entity = ecs.Entity;
const ComponentId = ecs.ComponentId;

const TestComponentOne = struct {
    field_one: u32,
    field_two: u32,
};

const TestComponentTwo = struct {
    field_one: u32,
    field_two: u32,
};

const TestComponentThree = struct {
    field_one: u32,
    field_two: u32,
};

const TestComponentFour = struct {
    field_one: u32,
    field_two: u32,
};

test "Archetype init and add" {
    const alloc = std.testing.allocator;
    var entity_id: Entity = 0;

    var archetype = Archetype.init(alloc, .{ TestComponentOne, TestComponentTwo });
    defer archetype.deinit();

    const test_comp_one = TestComponentOne{
        .field_one = 1,
        .field_two = 2,
    };
    const test_comp_two = TestComponentTwo{
        .field_one = 3,
        .field_two = 4,
    };

    // Adding here to try to catch memory leak
    var res = archetype.addEntity(entity_id, .{ test_comp_one, test_comp_two });
    entity_id += 1;
    var is_err = if (res) |_| false else |_| true;
    std.debug.assert(!is_err);

    // Since we sort the component ids before we register them, changing the order should not
    // result in a mismatch
    res = archetype.addEntity(entity_id, .{ test_comp_two, test_comp_one });
    entity_id += 1;
    is_err = if (res) |_| false else |_| true;
    std.debug.assert(!is_err);

    // But a total differing in struct should error
    res = archetype.addEntity(entity_id, .{test_comp_two});
    std.debug.assert(res == error.IncompatibleArchetype);

    // It should error out if the struct has different fields
    const test_comp_three = TestComponentThree{
        .field_one = 1,
        .field_two = 2,
    };
    res = archetype.addEntity(entity_id, .{ test_comp_one, test_comp_three });
    std.debug.assert(res == error.IncompatibleArchetype);
}

test "Archetype get columns" {
    const alloc = std.testing.allocator;
    var entity_id: Entity = 0;

    const test_comp_one = TestComponentOne{
        .field_one = 1,
        .field_two = 2,
    };
    const test_comp_two = TestComponentTwo{
        .field_one = 3,
        .field_two = 4,
    };
    const test_comp_three = TestComponentThree{
        .field_one = 3,
        .field_two = 4,
    };
    const test_comp_four = TestComponentFour{
        .field_one = 3,
        .field_two = 4,
    };

    var archetype_one = Archetype.init(alloc, .{ TestComponentOne, TestComponentTwo });
    defer archetype_one.deinit();

    var archetype_two = Archetype.init(alloc, .{ TestComponentThree, TestComponentFour });
    defer archetype_two.deinit();

    try archetype_one.addEntity(entity_id, .{ test_comp_one, test_comp_two });
    entity_id += 1;
    try archetype_two.addEntity(entity_id, .{ test_comp_three, test_comp_four });
    entity_id += 1;

    var component_ids_one: [2]u32 = undefined;
    component_ids_one[0] = ComponentId(TestComponentOne);
    component_ids_one[1] = ComponentId(TestComponentTwo);
    var component_ids_two: [2]u32 = undefined;
    component_ids_two[0] = ComponentId(TestComponentThree);
    component_ids_two[1] = ComponentId(TestComponentFour);
    std.debug.assert(archetype_one.signature.matches(&component_ids_one));
    std.debug.assert(archetype_two.signature.matches(&component_ids_two));

    const component_ones = archetype_one.getColumn(TestComponentOne);
    if (component_ones) |components| {
        for (components) |component| {
            std.debug.assert(component.field_one == 1);
            std.debug.assert(component.field_two == 2);
        }
    }

    const component_twos = archetype_one.getColumn(TestComponentTwo);
    if (component_twos) |components| {
        for (components) |component| {
            std.debug.assert(component.field_one == 3);
            std.debug.assert(component.field_two == 4);
        }
    }
}
