const std = @import("std");
const builtin = @import("builtin");
const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const slog = sokol.log;
const Allocator = std.mem.Allocator;
const util = @import("util.zig");

const spine_c = @cImport({
    @cInclude("spine/spine.h");
    @cInclude("spine/extension.h");
});

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

const game_state = struct {};

/// This is the main game loop
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = if (builtin.mode != .Debug)
        std.heap.page_allocator
    else
        gpa.allocator();

    const animation_mix = mix: {
        var map = std.StringHashMap(
            []struct { []const u8, []const u8 },
        ).init(allocator);
        const from_to_pairs = [_]struct { []const u8, []const u8 }{
            .{ "idle", "run" },
        };
        try map.put("0.1", @constCast(&from_to_pairs));
        break :mix map;
    };

    try util.loadAnimationData(allocator, "assets/spineboy-ess.atlas", animation_mix);
}
