const std = @import("std");
const builtin = @import("builtin");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const slog = sokol.log;
const sglue = sokol.glue;
const Allocator = std.mem.Allocator;
const util = @import("util.zig");
const spc = util.spine_c;
const zigimg = @import("zigimg");

const Renderable = @import("Renderable.zig");
const Aliens = @import("objects/Aliens.zig");
const Cursor = @import("Cursor.zig");
const SettingsMenu = @import("menus/SettingsMenu.zig");
const Widget = @import("menus/widget.zig").Widget;
const InitBundle = util.InitBundle;
const ecs = @import("ecs/root.zig");
const assets = @import("assets");

const pda = @import("pda");

pub const WINDOW_WIDTH: i32 = 800;
pub const WINDOW_HEIGHT: i32 = 600;
const SAMPLE_COUNT: i32 = 4;
const WINDOW_TITLE: []const u8 = "ssolo";

// This needs to be included here otherwise the static analysis would fail for undefined symbols
comptime {
    _ = @import("spine_c_impl.zig");
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const pass_action: sg.PassAction = .{ .colors = [_]sg.ColorAttachmentAction{ .{ .load_action = .CLEAR, .clear_value = .{ .r = 0.2, .g = 0.2, .b = 0.2, .a = 1.0 } }, .{}, .{}, .{} } };
var renderables: [100]Renderable = undefined;
var ren_idx: usize = 0;
var allocator: std.mem.Allocator = undefined;
var IS_IN_MENU: bool = false;

var system: getSystem() = undefined;

// TODO: move this to a more purposeful place
fn getSystem() type {
    const ALIEN_ASSET_FILE_STEM: []const u8 = "alien_ess";
    return ecs.System(10, &[_]ecs.RenderContext{
        // Alien
        .{
            .get_init_bundle_fn_ptr = struct {
                pub fn getInitBundle() !InitBundle {
                    return try util.getInitBundle(
                        ALIEN_ASSET_FILE_STEM,
                        0.5,
                        0.2,
                    );
                }
            }.getInitBundle,
            .get_pip_fn_ptr = struct {
                pub fn getPip() sg.Pipeline {
                    const shd = @import("shaders/alien_ess.glsl.zig");
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
            }.getPip,
            .get_sampler_fn_ptr = struct {
                pub fn getSampler() sg.Sampler {
                    return sg.makeSampler(.{});
                }
            }.getSampler,
            .get_view_fn_ptr = struct {
                pub fn getView(alloc: std.mem.Allocator) sg.View {
                    const image_buffer = comptime blk: {
                        break :blk @field(assets, std.fmt.comptimePrint("{s}_png", .{ALIEN_ASSET_FILE_STEM}));
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
            }.getView,
        },
    });
}

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
        .buffer_pool_size = 1024,
        .image_pool_size = 256,
        .sampler_pool_size = 128,
        .shader_pool_size = 64,
        .pipeline_pool_size = 128,
    });

    allocator = if (builtin.mode != .Debug)
        std.heap.page_allocator
    else
        gpa.allocator();

    system = getSystem().init(allocator) catch |e| {
        std.log.err("Error initializing system: {any}", .{e});
        unreachable;
    };

    // this is just for testing
    // TODO: abstract this in a method on the system
    {
        const RenderableComponent = ecs.components.Renderable;
        const world_level_id: usize = 0;
        var entity_bundle = ecs.EntityBundle.init(allocator, 0) catch unreachable;
        const init_bundle = &system.init_bundle[world_level_id];
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
        const movement_speed: ecs.components.MovementSpeed = .{ .speed_per_second = 20.0 };

        entity_bundle.addComponent(render_component) catch unreachable;
        entity_bundle.addComponent(player_controlled) catch unreachable;
        entity_bundle.addComponent(movement_speed) catch unreachable;

        const arch = ecs.Archetype.initWithEntityBundle(allocator, &entity_bundle) catch unreachable;
        system.addArchetype(arch) catch unreachable;
    }

    sapp.showMouse(false);
    sapp.lockMouse(true);
}

export fn frame() void {
    sg.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });
    const time_elapsed = sapp.frameDuration();
    _ = time_elapsed;

    system.update() catch unreachable;
    system.render() catch unreachable;

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    // We have to do the cleaning before we deinit the gpa otherwise we get memory leak warnings
    for (0..ren_idx) |i| {
        renderables[i].deinit();
    }
    if (builtin.mode == .Debug) {
        // TODO: need to actually surface the leak check here once we have event handler to run the cleanup
        _ = gpa.deinit();
    }
    sg.shutdown();
}

/// This is the main game loop
pub fn main() !void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = util.makeGlobalUserInputHandler(&renderables[0..100], &ren_idx),
        .width = WINDOW_WIDTH,
        .height = WINDOW_HEIGHT,
        .sample_count = SAMPLE_COUNT,
        .icon = .{ .sokol_default = true },
        .window_title = WINDOW_TITLE.ptr,
        .logger = .{ .func = slog.func },
    });
}
