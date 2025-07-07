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

const WINDOW_WIDTH: i32 = 800;
const WINDOW_HEIGHT: i32 = 600;
const SAMPLE_COUNT: i32 = 4;
const WINDOW_TITLE: []const u8 = "ssolo";

comptime {
    _ = @import("spine_c_impl.zig");
}

const Vertex = struct {
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    color: u32,
};

const game_state = struct {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator: Allocator = undefined;
    var image: sg.Image = undefined;

    var pip: sg.Pipeline = .{};
    var bind: sg.Bindings = .{};
    var pass_action: sg.PassAction = .{};
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

    util.loadAnimationData(allocator, "assets/alien-ess.atlas", animation_mix, &game_state.image) catch |err| {
        std.log.err("Failed to load animation data: {}", .{err});
    };
}

export fn frame() void {
    sg.beginPass(.{ .action = game_state.pass_action, .swapchain = sglue.swapchain() });
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
