const std = @import("std");
const ecs = @import("../src/ecs/root.zig");
const Archetype = ecs.Archetype;
const ArchetypeSignature = ecs.ArchetypeSignature;
const Entity = ecs.Entity;

const TestComponentOne = struct {
    field_one: u32,
    field_two: u32,
};

const TestComponentTwo = struct {
    field_one: u32,
    field_two: u32,
};

test "Archetype init" {
    const alloc = std.testing.allocator;
    var entity_id: Entity = 0;

    var archetype = Archetype.init(alloc);
    const test_comp_one = TestComponentOne{
        .field_one = 1,
        .field_two = 2,
    };
    const test_comp_two = TestComponentTwo{
        .field_one = 3,
        .field_two = 4,
    };

    // Adding here to try to catch memory leak
    try archetype.addEntity(entity_id, .{ test_comp_one, test_comp_two });
    entity_id += 1;

    archetype.deinit();
}

test "Archetype add entity" {
    const alloc = std.testing.allocator;
    var entity_id: Entity = 0;

    var archetype = Archetype.init(alloc);
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
    try archetype.addEntity(entity_id, .{ test_comp_one, test_comp_two });
    entity_id += 1;
}
