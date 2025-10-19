const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const sokol = @import("sokol");
const sg = sokol.gfx;
const spc = util.spine_c;
const shd = @import("../shaders/alien_ess.glsl.zig");
const zigimg = @import("zigimg");
const Event = sokol.app.Event;

const Renderable = @import("../Renderable.zig");
const RenderableError = Renderable.RenderableError;
const util = @import("../util.zig");
const Vertex = util.Vertex;
const assets = @import("assets");
const ecs = @import("../ecs/root.zig");

const ASSET_FILE_STEM: []const u8 = "alien_ess";
const MAX_ELEMENT: u64 = 10000;
const MAX_VERTICES_PER_ATTACHMENT = util.MAX_VERTICES_PER_ATTACHMENT;

get_system_init_fn_ptr: *const fn (*ecs.System, usize) void = systemInitRoutine,
get_init_bundle_fn_ptr: *const fn () anyerror!util.InitBundle = getInitBundle,
get_pip_fn_ptr: *const fn () sg.Pipeline = getPip,
get_sampler_fn_ptr: *const fn () sg.Sampler = getSampler,
get_view_fn_ptr: *const fn (std.mem.Allocator) sg.View = getView,

pub fn asRenderContext(self: @This()) ecs.RenderContext {
    return .{
        .get_init_routine_fn_ptr = self.get_system_init_fn_ptr,
        .get_init_bundle_fn_ptr = self.get_init_bundle_fn_ptr,
        .get_pip_fn_ptr = self.get_pip_fn_ptr,
        .get_sampler_fn_ptr = self.get_sampler_fn_ptr,
        .get_view_fn_ptr = self.get_view_fn_ptr,
    };
}

pub fn systemInitRoutine(system: *ecs.System, world_level_id: usize) void {
    const RenderableComponent = ecs.components.Renderable;
    const allocator = system.alloc;

    var entity_bundle = ecs.EntityBundle.init(allocator, 0) catch unreachable;
    const init_bundle = &system.init_bundles[world_level_id];
    const skeleton_data = init_bundle.skeleton_data;
    const animation_state_data = init_bundle.animation_state_data;

    const skeleton = spc.spSkeleton_create(skeleton_data);
    const animation = spc.spSkeletonData_findAnimation(skeleton_data, "hit");
    const state = spc.spAnimationState_create(animation_state_data);
    _ = spc.spAnimationState_setAnimation(state, 0, animation, 0);

    const render_component = RenderableComponent{
        .world_level_id = 0,
        .skeleton = skeleton,
        .animation_state = state,
        .vertex_buffer = sg.makeBuffer(.{
            .usage = .{ .dynamic_update = true },
            .size = util.MAX_VERTICES_PER_ATTACHMENT * @sizeOf(util.Vertex),
        }),
        .index_buffer = sg.makeBuffer(.{
            .usage = .{ .index_buffer = true, .dynamic_update = true },
            .size = util.MAX_VERTICES_PER_ATTACHMENT * @sizeOf(u16),
        }),
    };
    const player_controlled: ecs.components.PlayerControlled = .{};
    const movement_speed: ecs.components.MovementSpeed = .{ .speed_per_second = 200.0 };
    const input_handler: ecs.components.UserInputHandler = .{
        .handle_event_fn_ptr = util.handleUserInput,
    };

    entity_bundle.addComponent(render_component) catch unreachable;
    entity_bundle.addComponent(player_controlled) catch unreachable;
    entity_bundle.addComponent(movement_speed) catch unreachable;
    entity_bundle.addComponent(input_handler) catch unreachable;

    const arch = ecs.Archetype.initWithEntityBundle(allocator, &entity_bundle) catch unreachable;
    system.addArchetype(arch) catch unreachable;
}

fn getInitBundle() !util.InitBundle {
    return try util.getInitBundle(
        ASSET_FILE_STEM,
        0.5,
        0.2,
    );
}

fn getPip() sg.Pipeline {
    return sg.makePipeline(.{
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
        .cull_mode = .NONE,
        .colors = init: {
            var colors: [4]sg.ColorTargetState = undefined;
            var color = sg.ColorTargetState{};
            color.blend = .{
                .enabled = true,
                .src_factor_rgb = .ONE,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                .src_factor_alpha = .ONE,
                .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
            };
            colors[0] = color;
            break :init colors;
        },
    });
}

fn getSampler() sg.Sampler {
    return sg.makeSampler(.{});
}

fn getView(alloc: std.mem.Allocator) sg.View {
    const image_buffer = comptime blk: {
        break :blk @field(assets, std.fmt.comptimePrint("{s}_png", .{ASSET_FILE_STEM}));
    };
    var image = zigimg.Image.fromMemory(alloc, image_buffer) catch @panic("Error reading image from memory");
    defer image.deinit(alloc);
    const sprite_sheet = sg.makeImage(.{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .data = init: {
            var data = sg.ImageData{};
            data.mip_levels[0] = sg.asRange(image.pixels.rgba32);
            break :init data;
        },
    });
    return sg.makeView(.{
        .texture = .{ .image = sprite_sheet },
    });
}
