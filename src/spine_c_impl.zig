const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const zigimg = @import("zigimg");
const spine_c = @cImport({
    @cInclude("spine/spine.h");
    @cInclude("spine/extension.h");
});

export fn _spUtil_readFile(path: [*c]const u8, length: [*c]c_int) [*c]u8 {
    return spine_c._spReadFile(path, length);
}

// We have to break zig convention here and not include the allocator as part of the function signature
// because this signature is defined by the library (which is written in c).
export fn _spAtlasPage_createTexture(self: [*c]spine_c.spAtlasPage, path: [*c]const u8) void {
    const path_str: []const u8 = std.mem.span(path);
    const allocator = std.heap.c_allocator;

    // Load and parse image using zigimg
    var image_data = zigimg.Image.fromFilePath(allocator, path_str) catch |err| {
        std.log.err("Failed to load texture: {s}, error: {}", .{ path_str, err });
        return;
    };
    defer image_data.deinit();

    // Get actual image dimensions
    const width: i32 = @intCast(image_data.width);
    const height: i32 = @intCast(image_data.height);
    std.log.info("width={}, height={}", .{ width, height });

    const image = sg.makeImage(.{
        .width = width,
        .height = height,
        .data = init: {
            var data = sg.ImageData{};
            data.subimage[0][0] = sg.asRange(image_data.pixels.rgba32);
            break :init data;
        },
    });

    // Store texture and dimensions in the atlas page per spine-c documentation
    if (self) |atlas_page| {
        // atlas is the parent of atlas page.
        // The void* that occupies a rendererObject belongs to the atlas, not the atlas_page.
        // The intention is that each page is to access the same atlas
        if (atlas_page.*.atlas.*.rendererObject) |renderer_obj| {
            const image_ptr: *sg.Image = @ptrFromInt(@intFromPtr(renderer_obj));
            image_ptr.* = image;
        }
        atlas_page.*.width = width;
        atlas_page.*.height = height;
    }
}

export fn _spAtlasPage_disposeTexture(self: [*c]spine_c.spAtlasPage) void {
    if (self) |atlas_page| {
        if (atlas_page.*.rendererObject) |renderer_obj| {
            const image: sg.Image = .{ .id = @intCast(@intFromPtr(renderer_obj)) };
            sg.destroyImage(image);
            atlas_page.*.rendererObject = null;
        }
    }
}
