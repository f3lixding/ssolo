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

const WINDOW_WIDTH: i32 = 800;
const WINDOW_HEIGHT: i32 = 600;
const SAMPLE_COUNT: i32 = 4;
const WINDOW_TITLE: []const u8 = "ssolo";

// This needs to be included here otherwise the static analysis would fail for undefined symbols
comptime {
    _ = @import("spine_c_impl.zig");
}

const std_options = @import("log.zig");
const ssolo_log = std.log.scoped(.ssolo);

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const pass_action: sg.PassAction = .{
    .colors = [_]sg.ColorAttachmentAction{
        .{ .load_action = .CLEAR, .clear_value = .{ .r = 0.2, .g = 0.2, .b = 0.2, .a = 1.0 } },
        .{},
        .{},
        .{},
    },
};
var allocator: std.mem.Allocator = undefined;

var system: ecs.System = undefined;

// TODO: move this to a more purposeful place
fn getSystem(alloc: std.mem.Allocator) !ecs.System {
    const alien_render_ctx = @import("objects/Aliens.zig"){};
    const context = &[_]ecs.RenderContext{
        alien_render_ctx.asRenderContext(),
    };

    return ecs.System.init(alloc, context);
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

    system = getSystem(allocator) catch unreachable;

    sapp.showMouse(false);
    sapp.lockMouse(true);
}

export fn frame() void {
    sg.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });

    const time_elapsed = sapp.frameDuration();

    system.update(time_elapsed) catch unreachable;
    system.render() catch unreachable;

    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    system.deinit();

    if (builtin.mode == .Debug) {
        // Note: we need to deinit here otherwise any memory leaks is not going to be surfaced
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
        .event_cb = util.makeGlobalUserInputHandler(&system),
        .width = WINDOW_WIDTH,
        .height = WINDOW_HEIGHT,
        .sample_count = SAMPLE_COUNT,
        .icon = .{ .sokol_default = true },
        .window_title = WINDOW_TITLE.ptr,
        .logger = .{ .func = slog.func },
    });
}
