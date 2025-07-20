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

const Renderable = @import("Renderable.zig");

const Aliens = @import("objects/Aliens.zig");

const WINDOW_WIDTH: i32 = 800;
const WINDOW_HEIGHT: i32 = 600;
const SAMPLE_COUNT: i32 = 4;
const WINDOW_TITLE: []const u8 = "ssolo";

comptime {
    _ = @import("spine_c_impl.zig");
}

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const pass_action: sg.PassAction = .{ .colors = [_]sg.ColorAttachmentAction{ .{ .load_action = .CLEAR, .clear_value = .{ .r = 0.2, .g = 0.2, .b = 0.2, .a = 1.0 } }, .{}, .{}, .{} } };
var renderables: [100]Renderable = undefined;
var ren_idx: usize = 0;
// const game_state = struct {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     var allocator: Allocator = undefined;
//     var skel_data: *spine_c.spSkeletonData = undefined;
//     var skel: *spine_c.spSkeleton = undefined;
//     var animation_state: *spine_c.struct_spAnimationState = undefined;
//
//     var pip: sg.Pipeline = .{};
//     var bind: sg.Bindings = .{};
//     var pass_action: sg.PassAction = .{ .colors = [_]sg.ColorAttachmentAction{ .{ .load_action = .CLEAR, .clear_value = .{ .r = 0.2, .g = 0.2, .b = 0.2, .a = 1.0 } }, .{}, .{}, .{} } };
//     var vertex_buffer: sg.Buffer = .{};
//     var index_buffer: sg.Buffer = .{};
//     var sampler: sg.Sampler = .{};
// };

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    const allocator = if (builtin.mode != .Debug)
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

    for (0..ren_idx) |i| {
        renderables[i].init_inner(allocator) catch unreachable;
    }

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
        .width = WINDOW_HEIGHT,
        .height = WINDOW_HEIGHT,
        .sample_count = SAMPLE_COUNT,
        .icon = .{ .sokol_default = true },
        .window_title = WINDOW_TITLE.ptr,
        .logger = .{ .func = slog.func },
    });
}
