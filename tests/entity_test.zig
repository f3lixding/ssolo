const std = @import("std");
const ecs = @import("../src/ecs/root.zig");
const Archetype = ecs.Archetype;
const ArchetypeSignature = ecs.ArchetypeSignature;
const Entity = ecs.Entity;
const EntityBundle = ecs.EntityBundle;
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

test "archetype init with component ids and add" {
    const alloc = std.testing.allocator;
    var entity_id: Entity = 0;

    const components = .{ TestComponentOne, TestComponentTwo };
    const component_ids = sig: {
        const components_info = @typeInfo(@TypeOf(components));
        const fields = components_info.@"struct".fields;
        const component_ids = try alloc.alloc(u32, fields.len);
        inline for (fields, 0..) |field, i| {
            const @"type" = @field(components, field.name);
            const id = ComponentId(@"type");
            component_ids[i] = id;
        }
        std.mem.sort(u32, component_ids, {}, std.sort.asc(u32));
        break :sig component_ids;
    };
    defer alloc.free(component_ids);

    var archetype = Archetype.initWithComponentIds(alloc, component_ids) catch unreachable;
    defer archetype.deinit();

    const test_comp_one = TestComponentOne{
        .field_one = 1,
        .field_two = 2,
    };
    const test_comp_two = TestComponentTwo{
        .field_one = 3,
        .field_two = 4,
    };
    const res = archetype.addEntity(entity_id, .{ test_comp_one, test_comp_two });
    entity_id += 1;
    const is_err = if (res) |_| false else |_| true;
    std.debug.assert(!is_err);
}

test "archetype init and add" {
    const alloc = std.testing.allocator;
    var entity_id: Entity = 0;

    var archetype = Archetype.init(alloc, .{ TestComponentOne, TestComponentTwo }) catch unreachable;
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

test "achetype init and add with component byte arrays" {
    const alloc = std.testing.allocator;
    var entity_id: Entity = 0;

    var archetype = Archetype.init(alloc, .{ TestComponentOne, TestComponentTwo }) catch unreachable;
    defer archetype.deinit();

    const test_comp_one = TestComponentOne{
        .field_one = 1,
        .field_two = 2,
    };
    const test_comp_two = TestComponentTwo{
        .field_one = 3,
        .field_two = 4,
    };

    var entity_bundle = arr: {
        const comp_one_as_bytes = std.mem.asBytes(&test_comp_one);
        const comp_two_as_bytes = std.mem.asBytes(&test_comp_two);

        var comp_one_arr = std.ArrayList(u8).empty;
        try comp_one_arr.appendSlice(alloc, comp_one_as_bytes);
        var comp_two_arr = std.ArrayList(u8).empty;
        try comp_two_arr.appendSlice(alloc, comp_two_as_bytes);

        var bundle = try EntityBundle.init(alloc, entity_id);
        try bundle.components.put(ComponentId(@TypeOf(test_comp_one)), comp_one_arr);
        try bundle.components.put(ComponentId(@TypeOf(test_comp_two)), comp_two_arr);

        break :arr bundle;
    };
    const res = archetype.addEntityWithBundle(&entity_bundle);
    entity_id += 1;
    const is_err = if (res) |_| false else |_| true;
    std.debug.assert(!is_err);
}

test "achetype init with entity bundle" {
    const alloc = std.testing.allocator;
    const entity_id: Entity = 0;

    const test_comp_one = TestComponentOne{
        .field_one = 1,
        .field_two = 2,
    };
    const test_comp_two = TestComponentTwo{
        .field_one = 3,
        .field_two = 4,
    };

    var entity_bundle = arr: {
        const comp_one_as_bytes = std.mem.asBytes(&test_comp_one);
        const comp_two_as_bytes = std.mem.asBytes(&test_comp_two);

        var comp_one_arr = std.ArrayList(u8).init(std.testing.allocator);
        try comp_one_arr.appendSlice(comp_one_as_bytes);
        var comp_two_arr = std.ArrayList(u8).init(std.testing.allocator);
        try comp_two_arr.appendSlice(comp_two_as_bytes);

        var bundle = try EntityBundle.init(std.testing.allocator, entity_id);
        try bundle.components.put(ComponentId(@TypeOf(test_comp_one)), comp_one_arr);
        try bundle.components.put(ComponentId(@TypeOf(test_comp_two)), comp_two_arr);

        break :arr bundle;
    };

    var archetype = try Archetype.initWithEntityBundle(alloc, &entity_bundle);
    defer archetype.deinit();
}

test "archetype remove entity" {
    const alloc = std.testing.allocator;
    var entity_id: Entity = 0;

    var archetype = Archetype.init(alloc, .{ TestComponentOne, TestComponentTwo }) catch unreachable;
    defer archetype.deinit();

    const test_comp_one = TestComponentOne{
        .field_one = 1,
        .field_two = 2,
    };
    const test_comp_two = TestComponentTwo{
        .field_one = 3,
        .field_two = 4,
    };

    try archetype.addEntity(entity_id, .{ test_comp_one, test_comp_two });
    entity_id += 1;
    try archetype.addEntity(entity_id, .{ test_comp_one, test_comp_two });
    entity_id += 1;

    const to_remove = entity_id - 1;
    var res = archetype.removeEntity(to_remove);
    defer if (res) |*bundle| {
        bundle.deinit();
    } else |_| {};

    std.debug.assert(res != error.EntityNotFound);

    var unwrapped_res = res catch unreachable;
    const component_one_id = ComponentId(TestComponentOne);
    const component_one_array = unwrapped_res.components.get(component_one_id) orelse unreachable;
    const test_component_one = std.mem.bytesToValue(TestComponentOne, component_one_array.items[0..@sizeOf(TestComponentOne)]);
    std.debug.assert(test_component_one.field_one == 1);
    std.debug.assert(test_component_one.field_two == 2);

    std.debug.assert(archetype.entities_idx == 1);
    var iter = archetype.components_map.iterator();
    while (iter.next()) |entry| {
        const type_size = archetype.component_sizes.get(entry.key_ptr.*) orelse unreachable;
        const val = entry.value_ptr;
        std.debug.assert(val.items.len == type_size * 1);
    }
    std.debug.assert(archetype.entities.items.len == 1);
}

test "archetype get columns" {
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

    var archetype_one = Archetype.init(alloc, .{ TestComponentOne, TestComponentTwo }) catch unreachable;
    defer archetype_one.deinit();

    var archetype_two = Archetype.init(alloc, .{ TestComponentThree, TestComponentFour }) catch unreachable;
    defer archetype_two.deinit();

    try archetype_one.addEntity(entity_id, .{ test_comp_one, test_comp_two });
    entity_id += 1;
    try archetype_two.addEntity(entity_id, .{ test_comp_three, test_comp_four });
    entity_id += 1;

    var component_ids_one: [2]u32 = undefined;
    component_ids_one[0] = ComponentId(TestComponentOne);
    component_ids_one[1] = ComponentId(TestComponentTwo);
    std.mem.sort(u32, &component_ids_one, {}, std.sort.asc(u32));
    var component_ids_two: [2]u32 = undefined;
    component_ids_two[0] = ComponentId(TestComponentThree);
    component_ids_two[1] = ComponentId(TestComponentFour);
    std.mem.sort(u32, &component_ids_two, {}, std.sort.asc(u32));
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
