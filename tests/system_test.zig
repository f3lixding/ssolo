test "system init" {
    const ecs = @import("../src/ecs/root.zig");
    const sg = @import("sokol").gfx;
    const std = @import("std");

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
    }){};

    system.init(std.testing.allocator) catch |e| {
        std.debug.panic("Init errored: {any}\n", .{e});
    };
}

test "system create entity" {}
