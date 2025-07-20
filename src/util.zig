const std = @import("std");
const Allocator = std.mem.Allocator;
const assert = std.debug.assert;
const sg = @import("sokol").gfx;
pub const shd = @import("shaders/alien-ess.glsl.zig");

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

pub const MAX_VERTICES_PER_ATTACHMENT = 2048;

/// Refer to the Spine doc for more detail: https://esotericsoftware.com/spine-c#Loading-Spine-assets
/// The image pointer here is what is referred by the doc as "engine specific texture".
///
/// // Load the atlas from a file. The last argument is a void* that will be
/// // stored in atlas->rendererObject.
/// spAtlas* atlas = spAtlas_createFromFile("myatlas.atlas", 0);
///
/// Note that [spAtlas_createFromFile] eventually calls [_spAtlasPage_createTexture], where the aforementioned
/// atlas object is passed. The intention is to implement [_spAtlasPage_createTexture] such that the texture
/// loaded is then assigned to atlas->rendererObject.
pub fn loadAnimationData(
    alloc: Allocator,
    path: []const u8,
    animation_mix: std.StringHashMap(
        []struct { []const u8, []const u8 },
    ),
    skel_data: **spine_c.spSkeletonData,
    image: *sg.Image,
) !void {
    const atlas = spine_c.spAtlas_createFromFile(@ptrCast(path), @ptrCast(image));
    const binary = spine_c.spSkeletonBinary_create(atlas);
    defer spine_c.spSkeletonBinary_dispose(binary);
    binary.*.scale = 0.25;

    // We are going to assume the .skel file name is the same as the atlas file name
    const skel_path = dir: {
        const file_name = std.fs.path.stem(path);
        const dir_name = std.fs.path.dirname(path).?;
        break :dir std.fmt.allocPrint(alloc, "{s}/{s}.skel", .{ dir_name, file_name });
    } catch unreachable;
    defer alloc.free(skel_path);
    const skeleton_data = spine_c.spSkeletonBinary_readSkeletonDataFile(binary, @ptrCast(skel_path));

    skel_data.* = skeleton_data;

    // Prep animation state data
    const animation_state_data = spine_c.spAnimationStateData_create(skel_data.*);
    var mix_iter = animation_mix.iterator();
    while (mix_iter.next()) |entry| {
        const time = try std.fmt.parseFloat(f32, entry.key_ptr.*);
        for (entry.value_ptr.*) |*from_to_pair| {
            const from = from_to_pair.@"0";
            const to = from_to_pair.@"1";
            spine_c.spAnimationStateData_setMixByName(animation_state_data, @ptrCast(from), @ptrCast(to), time);
        }
    }
}

// pub fn collectSkeletonVertices(skel: *spine_c.spSkeleton, total_vertex_count: *usize) void {
//     const upper_bound: usize = @intCast(skel.slotsCount);
//     var i: usize = 0;
//
//     while (i < upper_bound) : (i += 1) {
//         const slot = skel.drawOrder[i];
//         const attach = slot.*.attachment;
//         if (attach) |attachment| {
//             if (attachment.*.type == spine_c.SP_ATTACHMENT_REGION) {
//                 const region_attachment: *spine_c.spRegionAttachment = @ptrCast(attachment);
//
//                 const tint_r: f32 = skel.color.r * slot.*.color.r * region_attachment.color.r;
//                 const tint_g: f32 = skel.color.g * slot.*.color.g * region_attachment.color.g;
//                 const tint_b: f32 = skel.color.b * slot.*.color.b * region_attachment.color.b;
//                 const tint_a: f32 = skel.color.a * slot.*.color.a * region_attachment.color.a;
//
//                 spine_c.spRegionAttachment_computeWorldVertices(
//                     region_attachment,
//                     slot,
//                     @ptrCast(&worldVerticesPositions),
//                     0,
//                     2,
//                 );
//                 // const atlas_region = @as(*spine_c.spAtlasRegion, @ptrCast(@alignCast(region_attachment.*.rendererObject)));
//                 // const atlas_page = atlas_region.*.page;
//                 // const renderer_obj = atlas_page.*.atlas.*.rendererObject.?;
//                 // texture = @ptrCast(@alignCast(renderer_obj));
//
//                 // Create 2 triangles, with 3 vertices each from the region's
//                 // world vertex positions and its UV coordinates (in the range [0-1]).
//                 addVertex(
//                     worldVerticesPositions[0],
//                     worldVerticesPositions[1],
//                     region_attachment.uvs[0],
//                     region_attachment.uvs[1],
//                     tint_r,
//                     tint_g,
//                     tint_b,
//                     tint_a,
//                     &total_vertex_count,
//                 );
//
//                 addVertex(
//                     worldVerticesPositions[2],
//                     worldVerticesPositions[3],
//                     region_attachment.uvs[2],
//                     region_attachment.uvs[3],
//                     tint_r,
//                     tint_g,
//                     tint_b,
//                     tint_a,
//                     &total_vertex_count,
//                 );
//
//                 addVertex(
//                     worldVerticesPositions[4],
//                     worldVerticesPositions[5],
//                     region_attachment.uvs[4],
//                     region_attachment.uvs[5],
//                     tint_r,
//                     tint_g,
//                     tint_b,
//                     tint_a,
//                     &total_vertex_count,
//                 );
//
//                 addVertex(
//                     worldVerticesPositions[4],
//                     worldVerticesPositions[5],
//                     region_attachment.uvs[4],
//                     region_attachment.uvs[5],
//                     tint_r,
//                     tint_g,
//                     tint_b,
//                     tint_a,
//                     &total_vertex_count,
//                 );
//
//                 addVertex(
//                     worldVerticesPositions[6],
//                     worldVerticesPositions[7],
//                     region_attachment.uvs[6],
//                     region_attachment.uvs[7],
//                     tint_r,
//                     tint_g,
//                     tint_b,
//                     tint_a,
//                     &total_vertex_count,
//                 );
//
//                 addVertex(
//                     worldVerticesPositions[0],
//                     worldVerticesPositions[1],
//                     region_attachment.uvs[0],
//                     region_attachment.uvs[1],
//                     tint_r,
//                     tint_g,
//                     tint_b,
//                     tint_a,
//                     &total_vertex_count,
//                 );
//             } else if (attachment.*.type == spine_c.SP_ATTACHMENT_MESH) {
//                 // noop for now. not sure what there is to do here.
//             }
//         }
//     }
// }

// pub fn renderCollectedVertices(
//     texture: ?*sg.Image,
//     pipeline: sg.Pipeline,
//     vertex_buffer: sg.Buffer,
//     index_buffer: sg.Buffer,
//     sampler: sg.Sampler,
// ) void {
//     if (total_vertex_count == 0 or texture == null) return;
//
//     // Update vertex buffer data once
//     sg.updateBuffer(vertex_buffer, sg.asRange(vertices[0..total_vertex_count]));
//
//     // Create indices for all quads
//     var indices: [MAX_VERTICES_PER_ATTACHMENT]u16 = undefined;
//     var index_count: usize = 0;
//
//     // Each region attachment creates 6 vertices in 2 triangles
//     // The vertices are arranged as: v0, v1, v2, v2, v3, v0 (forming a quad)
//     // We need to create proper triangle indices for this
//     var quad_count: usize = 0;
//     while (quad_count * 6 < total_vertex_count) {
//         const base_vertex: u16 = @intCast(quad_count * 6);
//
//         // First triangle: 0, 1, 2
//         indices[index_count] = base_vertex;
//         indices[index_count + 1] = base_vertex + 1;
//         indices[index_count + 2] = base_vertex + 2;
//
//         // Second triangle: 2, 3, 0 (which maps to vertices 3, 4, 5 in our layout)
//         indices[index_count + 3] = base_vertex + 3;
//         indices[index_count + 4] = base_vertex + 4;
//         indices[index_count + 5] = base_vertex + 5;
//
//         index_count += 6;
//         quad_count += 1;
//     }
//
//     sg.updateBuffer(index_buffer, sg.asRange(indices[0..index_count]));
//
//     // Create binding with pre-created buffers
//     const bind = sg.Bindings{
//         .vertex_buffers = ver: {
//             var buffers = [_]sg.Buffer{.{}} ** 8;
//             buffers[0] = vertex_buffer;
//             break :ver buffers;
//         },
//         .index_buffer = index_buffer,
//         .images = image: {
//             var images = [_]sg.Image{.{}} ** 16;
//             images[shd.IMG_tex] = texture.?.*;
//             break :image images;
//         },
//         .samplers = smp: {
//             var samplers = [_]sg.Sampler{.{}} ** 16;
//             samplers[shd.SMP_smp] = sampler;
//             break :smp samplers;
//         },
//     };
//
//     // Apply pipeline and draw
//     sg.applyPipeline(pipeline);
//     sg.applyBindings(bind);
//     sg.draw(0, @intCast(index_count), 1);
// }

// fn addVertex(
//     x: f32,
//     y: f32,
//     u: f32,
//     v: f32,
//     r: f32,
//     g: f32,
//     b: f32,
//     a: f32,
//     index: *usize,
// ) void {
//     const color = (@as(u32, @intFromFloat(r * 255.0)) << 24) |
//         (@as(u32, @intFromFloat(g * 255.0)) << 16) |
//         (@as(u32, @intFromFloat(b * 255.0)) << 8) |
//         (@as(u32, @intFromFloat(a * 255.0)));
//
//     // Convert from screen coordinates to normalized device coordinates (-1 to 1)
//     // Screen is 800x600, so normalize: x: [0, 800] -> [-1, 1], y: [0, 600] -> [-1, 1]
//     // TODO: make this dynamic so it scales with window size
//     const normalized_x = (x / 400.0); // 800/2 = 400
//     const normalized_y = (y / 300.0); // 600/2 = 300, no Y flip for now
//
//     vertices[index.*] = Vertex{
//         .x = normalized_x,
//         .y = normalized_y,
//         .u = u,
//         .v = v,
//         .color = color,
//     };
//
//     index.* += 1;
// }
