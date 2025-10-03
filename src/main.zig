const std = @import("std");
const builtin = @import("builtin");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const slog = sokol.log;
const sglue = sokol.glue;
const Allocator = std.mem.Allocator;
const util = @import("util.zig");
const spinec_c = util.spine_c;

const Renderable = @import("Renderable.zig");
const Aliens = @import("objects/Aliens.zig");
const Cursor = @import("Cursor.zig");
const SettingsMenu = @import("menus/SettingsMenu.zig");
const Widget = @import("menus/widget.zig").Widget;
const ecs = @import("ecs/root.zig");

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

// TODO: move this to a more purposeful place
fn getSystem() type {
    return ecs.System(10, &[_]ecs.RenderContext{
        // Alien
        .{
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
                pub fn getView() sg.View {
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
                        .texture = .{ .image = self.sprite_sheet },
                    });
                }
            }.getView,
        },
        // Menu
        .{
            .get_pip_fn_ptr = struct {
                pub fn getPip() sg.Pipeline {
                    return sg.Pipeline{};
                }
            }.getPip,
            .get_sampler_fn_ptr = struct {
                pub fn getSampler() sg.Sampler {
                    return sg.Sampler{};
                }
            }.getSampler,
            .get_view_fn_ptr = struct {
                pub fn getView() sg.View {
                    return sg.View{};
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

    const aliens = allocator.create(Aliens) catch |e| {
        std.log.err("Error creating aliens {any}", .{e});
        unreachable;
    };
    aliens.* = Aliens{};
    renderables[ren_idx] = Renderable.init(aliens) catch |e| {
        std.log.err("Error erasing type {any}", .{e});
        unreachable;
    };
    ren_idx += 1;

    // menu
    const WrappedMenu = Widget(.{
        .CoreType = SettingsMenu,
    });
    const wrapped_menu = allocator.create(WrappedMenu) catch |e| {
        std.log.err("Error creating menu {any}", .{e});
        unreachable;
    };
    wrapped_menu.* = WrappedMenu{
        .alloc = allocator,
        .core = SettingsMenu{},
    };
    renderables[ren_idx] = Renderable.init(wrapped_menu) catch |e| {
        std.log.err("Error erasing type {any}", .{e});
        unreachable;
    };
    ren_idx += 1;

    // cursor
    const cursor = allocator.create(Cursor) catch |e| {
        std.log.err("Error creating cursor {any}", .{e});
        unreachable;
    };
    cursor.* = Cursor{};
    renderables[ren_idx] = Renderable.init(cursor) catch |e| {
        std.log.err("Error erasing type {any}", .{e});
        unreachable;
    };
    ren_idx += 1;

    for (0..ren_idx) |i| {
        renderables[i].initInner(allocator) catch unreachable;
    }

    sapp.showMouse(false);
    sapp.lockMouse(true);

    // adding another one just for funzies
    aliens.add_instance(50.0, 50.0) catch |e| {
        std.log.err("Error adding another instance: {any}", .{e});
        unreachable;
    };
}

export fn frame() void {
    sg.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });
    const time_elapsed = sapp.frameDuration();
    for (0..ren_idx) |i| {
        renderables[i].update(@floatCast(time_elapsed)) catch |e| {
            std.log.err("Error updating renderable: {any}", .{e});
            unreachable;
        };
        renderables[i].render() catch |e| {
            std.log.err("Error rendering renderable: {any}", .{e});
            unreachable;
        };
    }
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
