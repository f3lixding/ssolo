const sg = @import("sokol").gfx;
const std = @import("std");
const alloc = std.testing.allocator;

const ecs = @import("../src/ecs/root.zig");
const Archetype = ecs.Archetype;
const AchetypeSignature = ecs.ArchetypeSignature;

const TestComponentOne = struct {
    field_one: u32,
    field_two: u32,
};

const TestComponentTwo = struct {
    field_three: u32,
    field_four: u32,
};

test "system init" {
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

    system.init(std.testing.allocator) catch |e| {
        std.debug.panic("Init errored: {any}\n", .{e});
    };
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
}
