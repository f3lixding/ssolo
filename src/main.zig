const std = @import("std");
const builtin = @import("builtin");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const slog = sokol.log;
const sglue = sokol.glue;
const Allocator = std.mem.Allocator;
const util = @import("util.zig");
const spine_c = @cImport({
    @cInclude("spine/spine.h");
    @cInclude("spine/extension.h");
});

const shd = @import("shaders/alien-ess.glsl.zig");

const WINDOW_WIDTH: i32 = 800;
const WINDOW_HEIGHT: i32 = 600;
const SAMPLE_COUNT: i32 = 4;
const WINDOW_TITLE: []const u8 = "ssolo";

comptime {
    _ = @import("spine_c_impl.zig");
}

const game_state = struct {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator: Allocator = undefined;
    var skel_data: *spine_c.spSkeletonData = undefined;
    var skel: *spine_c.spSkeleton = undefined;

    var pip: sg.Pipeline = .{};
    var bind: sg.Bindings = .{};
    var pass_action: sg.PassAction = .{ .colors = [_]sg.ColorAttachmentAction{ .{ .load_action = .CLEAR, .clear_value = .{ .r = 0.2, .g = 0.2, .b = 0.2, .a = 1.0 } }, .{}, .{}, .{} } };
    var vertex_buffer: sg.Buffer = .{};
    var index_buffer: sg.Buffer = .{};
    var sampler: sg.Sampler = .{};
    var test_texture: sg.Image = .{};
};

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    const allocator = if (builtin.mode != .Debug)
        std.heap.page_allocator
    else
        game_state.gpa.allocator();

    const animation_mix = mix: {
        var map = std.StringHashMap(
            []struct { []const u8, []const u8 },
        ).init(allocator);
        const from_to_pairs = [_]struct { []const u8, []const u8 }{
            .{ "hit", "death" },
            .{ "run", "jump" },
        };
        map.put("0.1", @constCast(&from_to_pairs)) catch unreachable;
        break :mix map;
    };

    util.loadAnimationData(
        allocator,
        "assets/alien-ess.atlas",
        animation_mix,
        &game_state.skel_data,
        &game_state.bind.images[shd.IMG_tex],
    ) catch |err| {
        std.log.err("Failed to load animation data: {}", .{err});
    };

    game_state.skel = spine_c.spSkeleton_create(game_state.skel_data);

    // Create shader and pipeline once during initialization
    game_state.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.alienEssShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_alien_ess_pos].format = .FLOAT2;
            l.attrs[shd.ATTR_alien_ess_uv0].format = .FLOAT2;
            l.attrs[shd.ATTR_alien_ess_color0].format = .UBYTE4N;
            break :init l;
        },
        .index_type = .UINT16,
        .depth = .{
            .compare = .ALWAYS,
            .write_enabled = false,
        },
        .cull_mode = .BACK,
        .colors = init: {
            var colors: [4]sg.ColorTargetState = undefined;
            var color = sg.ColorTargetState{};
            color.blend = .{
                .enabled = true,
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                .src_factor_alpha = .ONE,
                .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
            };
            colors[0] = color;
            break :init colors;
        },
    });

    // Create buffers and sampler once during initialization
    game_state.vertex_buffer = sg.makeBuffer(.{
        .usage = .{ .dynamic_update = true },
        .size = util.MAX_VERTICES_PER_ATTACHMENT * @sizeOf(util.Vertex),
    });

    game_state.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true, .dynamic_update = true },
        .size = util.MAX_VERTICES_PER_ATTACHMENT * @sizeOf(u16),
    });

    game_state.sampler = sg.makeSampler(.{});
}

export fn frame() void {
    sg.beginPass(.{ .action = game_state.pass_action, .swapchain = sglue.swapchain() });
    util.collectSkeletonVertices(game_state.skel);
    // binds and pip are applied in this function so we don't have to do it again outside of this
    util.renderCollectedVertices(
        &game_state.bind.images[shd.IMG_tex],
        game_state.pip,
        game_state.vertex_buffer,
        game_state.index_buffer,
        game_state.sampler,
    );
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    if (builtin.mode == .Debug) {
        // TODO: need to actually surface the leak check here once we have event handler to run the cleanup
        _ = game_state.gpa.deinit();
    }
    sg.shutdown();
}

/// This is the main game loop
pub fn main() !void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .width = WINDOW_HEIGHT,
        .height = WINDOW_HEIGHT,
        .sample_count = SAMPLE_COUNT,
        .icon = .{ .sokol_default = true },
        .window_title = WINDOW_TITLE.ptr,
        .logger = .{ .func = slog.func },
    });
}
