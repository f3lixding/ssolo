const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const sokol = @import("sokol");
const sg = sokol.gfx;
const spc = util.spine_c;
const shd = @import("../shaders/alien-ess.glsl.zig");

const Renderable = @import("../Renderable.zig");
const RenderableError = Renderable.RenderableError;
const util = @import("../util.zig");
const Vertex = util.Vertex;

const ASSET_FILE_STEM: []const u8 = "alien-ess";
const MAX_ELEMENT: u64 = 100;
const MAX_VERTICES_PER_ATTACHMENT = util.MAX_VERTICES_PER_ATTACHMENT;

const AlienError = error{Full};

// we'll use a predetermined length for now
// in the future we shall perhaps make this struct a generic that takes this in as a parameter
collections: [MAX_ELEMENT]Alien = undefined,
current_idx: usize = 0,
skeleton_data: *spc.struct_spSkeletonData = undefined,
animation_state_data: *spc.struct_spAnimationStateData = undefined,
sprite_sheet: sg.Image = undefined,
sampler: sg.Sampler = undefined,
shader: sg.Shader = undefined,
pip: sg.Pipeline = undefined,

pub fn init(self: *@This(), alloc: Allocator) RenderableError!void {
    const bin_path = try std.fmt.allocPrint(alloc, "assets/{s}.skel", .{ASSET_FILE_STEM});
    defer alloc.free(bin_path);
    const atlas_path = try std.fmt.allocPrint(alloc, "assets/{s}.atlas", .{ASSET_FILE_STEM});
    defer alloc.free(atlas_path);

    const atlas = spc.spAtlas_createFromFile(@ptrCast(atlas_path), @ptrCast(&self.sprite_sheet));
    const binary = spc.spSkeletonBinary_create(atlas);
    defer spc.spSkeletonBinary_dispose(binary);
    binary.*.scale = 0.2;

    self.skeleton_data = spc.spSkeletonBinary_readSkeletonDataFile(binary, @ptrCast(bin_path));

    self.animation_state_data = spc.spAnimationStateData_create(self.skeleton_data);
    self.animation_state_data.defaultMix = 0.5;

    self.pip = sg.makePipeline(.{
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
        .cull_mode = .BACK,
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

    self.sampler = sg.makeSampler(.{});

    // We default to having one instance for now:
    self.add_instance(0.0, 0.0) catch |e| {
        switch (e) {
            error.Full => {
                std.log.info("Alien collections are full. Cannot add anymore", .{});
            },
        }
    };
}

// Maybe make this method public?
pub fn add_instance(self: *@This(), init_x: f32, init_y: f32) AlienError!void {
    if (self.current_idx >= MAX_ELEMENT) {
        std.log.info("current_idx: {d}", .{self.current_idx});
        return AlienError.Full;
    }

    const to_add = Alien{
        .skeleton = init: {
            const skeleton = spc.spSkeleton_create(self.skeleton_data);
            skeleton.*.x = init_x;
            skeleton.*.y = init_y;
            break :init skeleton;
        },
        .animation_state = init: {
            const state = spc.spAnimationState_create(self.animation_state_data);
            // we'll start with running
            const animation = spc.spSkeletonData_findAnimation(self.skeleton_data, "run");
            _ = spc.spAnimationState_setAnimation(state, 0, animation, 1);
            break :init state;
        },
        .vertex_buffer = sg.makeBuffer(.{
            .usage = .{ .dynamic_update = true },
            .size = MAX_VERTICES_PER_ATTACHMENT * @sizeOf(Vertex),
        }),
        .index_buffer = sg.makeBuffer(.{
            .usage = .{ .index_buffer = true, .dynamic_update = true },
            .size = MAX_VERTICES_PER_ATTACHMENT * @sizeOf(u16),
        }),
    };

    self.collections[self.current_idx] = to_add;
    self.current_idx += 1;
}

pub fn update(self: *@This(), dt: f32) RenderableError!void {
    _ = dt;
    for (0..self.current_idx) |i| {
        self.collections[i].update();
    }
}

pub fn render(self: *const @This()) RenderableError!void {
    for (0..self.current_idx) |i| {
        const image_ptr: *sg.Image = @constCast(&self.sprite_sheet);
        self.collections[i].render(image_ptr, self.pip, self.sampler) catch |e| {
            std.log.err("Error encountered while rendering alien instance: {any}", .{e});
            return RenderableError.RenderError;
        };
    }
}

pub fn deinit(self: *const @This(), alloc: Allocator) void {
    _ = self;
    _ = alloc;
}

const Alien = struct {
    skeleton: *spc.spSkeleton,
    animation_state: *spc.spAnimationState,
    vertex_buffer: sg.Buffer,
    index_buffer: sg.Buffer,
    vertices: [MAX_VERTICES_PER_ATTACHMENT]Vertex = undefined,
    total_vertex_count: usize = 0,
    world_vertices_pos: [MAX_VERTICES_PER_ATTACHMENT]f32 = undefined,

    pub fn update(self: *Alien) void {
        // first we need to update the animation state
        spc.spAnimationState_update(self.animation_state, 0.01);
        _ = spc.spAnimationState_apply(self.animation_state, self.skeleton);
        spc.spSkeleton_updateWorldTransform(self.skeleton, spc.SP_PHYSICS_NONE);
        // and then we update vertex info
        self.total_vertex_count = 0;

        const upper_bound: usize = @intCast(self.skeleton.slotsCount);
        var i: usize = 0;

        while (i < upper_bound) : (i += 1) {
            const slot = self.skeleton.drawOrder[i];
            const attach = slot.*.attachment;
            if (attach) |attachment| {
                if (attachment.*.type == spc.SP_ATTACHMENT_REGION) {
                    const region_attachment: *spc.spRegionAttachment = @ptrCast(attachment);

                    const tint_r: f32 = self.skeleton.color.r * slot.*.color.r * region_attachment.color.r;
                    const tint_g: f32 = self.skeleton.color.g * slot.*.color.g * region_attachment.color.g;
                    const tint_b: f32 = self.skeleton.color.b * slot.*.color.b * region_attachment.color.b;
                    const tint_a: f32 = self.skeleton.color.a * slot.*.color.a * region_attachment.color.a;

                    spc.spRegionAttachment_computeWorldVertices(
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
                    self.addVertex(
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

                    self.addVertex(
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

                    self.addVertex(
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

                    self.addVertex(
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

                    self.addVertex(
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

                    self.addVertex(
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
                } else if (attachment.*.type == spc.SP_ATTACHMENT_MESH) {
                    // noop for now. not sure what there is to do here.
                }
            }
        }
    }

    pub fn render(
        self: Alien,
        texture: *sg.Image,
        pip: sg.Pipeline,
        sampler: sg.Sampler,
    ) !void {
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

    fn addVertex(
        self: *Alien,
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
};
