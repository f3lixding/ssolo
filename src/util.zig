const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const sg = @import("sokol").gfx;
pub const shd = @import("shaders/alien_ess.glsl.zig");
const assets = @import("assets");
const Event = @import("sokol").app.Event;
const Renderable = @import("Renderable.zig");
const RenderableError = Renderable.RenderableError;

pub const spine_c = @cImport({
    @cInclude("spine/spine.h");
    @cInclude("spine/extension.h");
});

pub const Vertex = struct {
    x: f32,
    y: f32,
    color: u32,
    u: f32,
    v: f32,
};

pub const InitBundle = struct {
    skeleton_data: *spine_c.spSkeletonData,
    animation_state_data: *spine_c.spAnimationStateData,
};

pub const MAX_VERTICES_PER_ATTACHMENT = 2048;

pub fn getInitBundle(
    comptime asset_name: []const u8,
    default_mix: f32,
    scale: f32,
) !InitBundle {
    const atlas_data = comptime blk: {
        const field_name = std.fmt.comptimePrint("{s}_atlas", .{asset_name});
        break :blk @field(assets, field_name);
    };

    const binary_data = comptime blk: {
        const field_name = std.fmt.comptimePrint("{s}_skel", .{asset_name});
        break :blk @field(assets, field_name);
    };

    const atlas = spine_c.spAtlas_create(
        @ptrCast(atlas_data.ptr),
        @intCast(atlas_data.len),
        @ptrCast(""),
        null,
    );
    const binary = spine_c.spSkeletonBinary_create(atlas);
    defer spine_c.spSkeletonBinary_dispose(binary);
    binary.*.scale = scale;

    const skeleton_data = spine_c.spSkeletonBinary_readSkeletonData(binary, @ptrCast(binary_data), binary_data.len);
    const animation_state_data = spine_c.spAnimationStateData_create(skeleton_data);
    animation_state_data.*.defaultMix = default_mix;

    return .{
        .skeleton_data = skeleton_data,
        .animation_state_data = animation_state_data,
    };
}

/// Objects should be free to make their own pipeline if the situation calls for it.
/// Otherwise from the spine example it looks like the vertex layout state are all
/// pretty much the same for all attachments
pub fn makePipeline(shader_desc: sg.ShaderDesc) sg.Pipeline {
    return sg.makePipeline(.{
        .shader = sg.makeShader(shader_desc),
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
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                .src_factor_alpha = .ONE,
                .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
            };
            colors[0] = color;
            break :init colors;
        },
    });
}

/// spine_c specific updates.
/// To be called prior to instance specific updates that are not spine_c specific.
/// Also note that this does not take into account attachment specific update
pub fn update(self: anytype) void {
    // negative space
    const PtrInfo = @typeInfo(@TypeOf(self));
    if (PtrInfo != .pointer) {
        @compileError("Expected a pointer type to be passed in");
    }
    const T = PtrInfo.pointer.child;

    comptime {
        assert(@hasField(T, "skeleton"));
        assert(@hasField(T, "world_vertices_pos"));
        assert(@hasField(T, "total_vertex_count"));
        assert(@hasField(T, "should_animate"));
    }

    // first we need to update the animation state
    if (self.should_animate) {
        spine_c.spAnimationState_update(self.animation_state, 0.01);
        _ = spine_c.spAnimationState_apply(self.animation_state, self.skeleton);
    }
    spine_c.spSkeleton_updateWorldTransform(self.skeleton, spine_c.SP_PHYSICS_NONE);
    // and then we update vertex info
    self.total_vertex_count = 0;

    const upper_bound: usize = @intCast(self.skeleton.slotsCount);
    var i: usize = 0;

    while (i < upper_bound) : (i += 1) {
        const slot = self.skeleton.drawOrder[i];
        const attach = slot.*.attachment;
        if (attach) |attachment| {
            if (attachment.*.type == spine_c.SP_ATTACHMENT_REGION) {
                const region_attachment: *spine_c.spRegionAttachment = @ptrCast(attachment);

                const tint_r: f32 = self.skeleton.color.r * slot.*.color.r * region_attachment.color.r;
                const tint_g: f32 = self.skeleton.color.g * slot.*.color.g * region_attachment.color.g;
                const tint_b: f32 = self.skeleton.color.b * slot.*.color.b * region_attachment.color.b;
                const tint_a: f32 = self.skeleton.color.a * slot.*.color.a * region_attachment.color.a;

                spine_c.spRegionAttachment_computeWorldVertices(
                    region_attachment,
                    slot,
                    @ptrCast(&self.world_vertices_pos),
                    0,
                    2,
                );
                // const atlas_region = @as(*spine_c.spAtlasRegion, @ptrCast(@alignCast(region_attachment.*.rendererObject)));
                // const atlas_page = atlas_region.*.page;
                // const renderer_obj = atlas_page.*.atlas.*.rendererObject.?;
                // texture = @ptrCast(@alignCast(renderer_obj));

                // Create 2 triangles, with 3 vertices each from the region's
                // world vertex positions and its UV coordinates (in the range [0-1]).
                addVertex(
                    self,
                    self.world_vertices_pos[0],
                    self.world_vertices_pos[1],
                    region_attachment.uvs[0],
                    region_attachment.uvs[1],
                    tint_r,
                    tint_g,
                    tint_b,
                    tint_a,
                    &self.total_vertex_count,
                );

                addVertex(
                    self,
                    self.world_vertices_pos[2],
                    self.world_vertices_pos[3],
                    region_attachment.uvs[2],
                    region_attachment.uvs[3],
                    tint_r,
                    tint_g,
                    tint_b,
                    tint_a,
                    &self.total_vertex_count,
                );

                addVertex(
                    self,
                    self.world_vertices_pos[4],
                    self.world_vertices_pos[5],
                    region_attachment.uvs[4],
                    region_attachment.uvs[5],
                    tint_r,
                    tint_g,
                    tint_b,
                    tint_a,
                    &self.total_vertex_count,
                );

                addVertex(
                    self,
                    self.world_vertices_pos[4],
                    self.world_vertices_pos[5],
                    region_attachment.uvs[4],
                    region_attachment.uvs[5],
                    tint_r,
                    tint_g,
                    tint_b,
                    tint_a,
                    &self.total_vertex_count,
                );

                addVertex(
                    self,
                    self.world_vertices_pos[6],
                    self.world_vertices_pos[7],
                    region_attachment.uvs[6],
                    region_attachment.uvs[7],
                    tint_r,
                    tint_g,
                    tint_b,
                    tint_a,
                    &self.total_vertex_count,
                );

                addVertex(
                    self,
                    self.world_vertices_pos[0],
                    self.world_vertices_pos[1],
                    region_attachment.uvs[0],
                    region_attachment.uvs[1],
                    tint_r,
                    tint_g,
                    tint_b,
                    tint_a,
                    &self.total_vertex_count,
                );
            } else if (attachment.*.type == spine_c.SP_ATTACHMENT_MESH) {
                // noop for now. not sure what there is to do here.
            }
        }
    }
}

pub fn addVertex(
    self: anytype,
    x: f32,
    y: f32,
    u: f32,
    v: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
    index: *usize,
) void {
    const PtrInfo = @typeInfo(@TypeOf(self));
    if (PtrInfo != .pointer) {
        @compileError("Expected pointer type");
    }
    const T = PtrInfo.pointer.child;

    comptime {
        assert(@hasField(T, "vertices"));
    }

    const color = (@as(u32, @intFromFloat(r * 255.0)) << 24) |
        (@as(u32, @intFromFloat(g * 255.0)) << 16) |
        (@as(u32, @intFromFloat(b * 255.0)) << 8) |
        (@as(u32, @intFromFloat(a * 255.0)));

    // Convert from screen coordinates to normalized device coordinates (-1 to 1)
    // Screen is 800x600, so normalize: x: [0, 800] -> [-1, 1], y: [0, 600] -> [-1, 1]
    // TODO: make this dynamic so it scales with window size
    const normalized_x = (x / 400.0); // 800/2 = 400
    const normalized_y = (y / 300.0); // 600/2 = 300, no Y flip for now

    self.vertices[index.*] = Vertex{
        .x = normalized_x,
        .y = normalized_y,
        .u = u,
        .v = v,
        .color = color,
    };

    index.* += 1;
}

pub fn render(
    self: anytype,
    texture: *sg.Image,
    pip: sg.Pipeline,
    sampler: sg.Sampler,
) void {
    const TypeInfo = @typeInfo(@TypeOf(self));
    const T = switch (TypeInfo) {
        .pointer => |p| p.child,
        .@"struct" => |_| @TypeOf(self),
        else => @compileError("Unsupported type passed to render util function"),
    };

    comptime {
        assert(@hasField(T, "vertices"));
    }

    sg.updateBuffer(self.vertex_buffer, sg.asRange(self.vertices[0..self.total_vertex_count]));

    var indices: [MAX_VERTICES_PER_ATTACHMENT]u16 = undefined;
    var index_count: usize = 0;

    // Each region attachment creates 6 vertices in 2 triangles
    // The vertices are arranged as: v0, v1, v2, v2, v3, v0 (forming a quad)
    // We need to create proper triangle indices for this
    var quad_count: usize = 0;
    while (quad_count * 6 < self.total_vertex_count) {
        const base_vertex: u16 = @intCast(quad_count * 6);

        // First triangle: 0, 1, 2
        indices[index_count] = base_vertex;
        indices[index_count + 1] = base_vertex + 1;
        indices[index_count + 2] = base_vertex + 2;

        // Second triangle: 2, 3, 0 (which maps to vertices 3, 4, 5 in our layout)
        indices[index_count + 3] = base_vertex + 3;
        indices[index_count + 4] = base_vertex + 4;
        indices[index_count + 5] = base_vertex + 5;

        index_count += 6;
        quad_count += 1;
    }

    sg.updateBuffer(self.index_buffer, sg.asRange(indices[0..index_count]));

    const bind = sg.Bindings{
        .vertex_buffers = ver: {
            var buffers = [_]sg.Buffer{.{}} ** 8;
            buffers[0] = self.vertex_buffer;
            break :ver buffers;
        },
        .index_buffer = self.index_buffer,
        .images = image: {
            var images = [_]sg.Image{.{}} ** 16;
            images[shd.IMG_tex] = texture.*;
            break :image images;
        },
        .samplers = smp: {
            var samplers = [_]sg.Sampler{.{}} ** 16;
            samplers[shd.SMP_smp] = sampler;
            break :smp samplers;
        },
    };

    sg.applyPipeline(pip);
    sg.applyBindings(bind);
    sg.draw(0, @intCast(index_count), 1);
}

var cur_idx_ptr: *const usize = undefined;
var captured_renderables: *const []Renderable = undefined;

pub export fn makeGlobalUserInputHandler(renderables: *const []Renderable, cur_idx: *const usize) *const fn ([*c]const Event) callconv(.c) void {
    cur_idx_ptr = cur_idx;
    captured_renderables = renderables;

    const cb_struct = struct {
        pub export fn handleUserInput(event: [*c]const Event) void {
            for (0..cur_idx_ptr.*) |i| {
                captured_renderables.*[i].inputEventHandle(event) catch unreachable;
            }
        }
    };

    return cb_struct.handleUserInput;
}

test "mock test" {
    const val = spine_c.abs(0);
    std.debug.print("val is {d}\n", .{val});
}
