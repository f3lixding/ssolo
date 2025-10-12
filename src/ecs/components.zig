const util = @import("../util.zig");
const spc = util.spine_c;
const sg = @import("sokol").gfx;

const Vertex = util.Vertex;

const MAX_VERTICES_PER_ATTACHMENT = util.MAX_VERTICES_PER_ATTACHMENT;

pub const Position = struct { x: f32, y: f32 };

pub const Renderable = struct {
    world_level_id: usize,
    skeleton: *spc.spSkeleton,
    animation_state: *spc.spAnimationState,
    vertex_buffer: sg.Buffer,
    index_buffer: sg.Buffer,
    vertices: [MAX_VERTICES_PER_ATTACHMENT]Vertex = undefined,
    total_vertex_count: usize = 0,
    world_vertices_pos: [MAX_VERTICES_PER_ATTACHMENT]f32 = undefined,
};

pub const PlayerControlled = struct {
    is_enabled: bool = true,
};

pub const MovementSpeed = struct {
    speed_per_second: f32,
};

pub fn ComponentId(comptime ComponentType: type) u32 {
    const std = @import("std");
    const type_name = @typeName(ComponentType);

    return @truncate(std.hash_map.hashString(type_name));
}
