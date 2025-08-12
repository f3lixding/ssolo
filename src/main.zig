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

const pda = @import("pda");

pub const WINDOW_WIDTH: i32 = 800;
pub const WINDOW_HEIGHT: i32 = 600;
const SAMPLE_COUNT: i32 = 4;
const WINDOW_TITLE: []const u8 = "ssolo";

comptime {
    _ = @import("spine_c_impl.zig");
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const pass_action: sg.PassAction = .{ .colors = [_]sg.ColorAttachmentAction{ .{ .load_action = .CLEAR, .clear_value = .{ .r = 0.2, .g = 0.2, .b = 0.2, .a = 1.0 } }, .{}, .{}, .{} } };
var renderables: [100]Renderable = undefined;
var ren_idx: usize = 0;
var allocator: std.mem.Allocator = undefined;
var IS_IN_MENU: bool = false;

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
