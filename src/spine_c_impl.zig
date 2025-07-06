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

    // Convert image to RGBA8 format
    var rgba_pixels: []u8 = undefined;
    switch (image_data.pixels) {
        .rgba32 => |pixels| {
            rgba_pixels = std.mem.sliceAsBytes(pixels);
        },
        .rgb24 => |pixels| {
            // Convert RGB24 to RGBA32
            rgba_pixels = allocator.alloc(u8, pixels.len * 4 / 3) catch {
                std.log.err("Failed to allocate memory for RGBA conversion", .{});
                return;
            };
            var i: usize = 0;
            var j: usize = 0;
            while (i < pixels.len) : (i += 1) {
                rgba_pixels[j] = pixels[i].r; // R
                rgba_pixels[j + 1] = pixels[i].g; // G
                rgba_pixels[j + 2] = pixels[i].b; // B
                rgba_pixels[j + 3] = 255; // A
                j += 4;
            }
        },
        else => {
            std.log.err("Unsupported image format for texture: {s}", .{path_str});
            return;
        },
    }
    defer if (image_data.pixels != .rgba32) allocator.free(rgba_pixels);

    // Create sokol texture
    var texture_desc = sg.ImageDesc{
        .width = width,
        .height = height,
        .pixel_format = .RGBA8,
    };
    texture_desc.data.subimage[0][0] = .{ .ptr = rgba_pixels.ptr, .size = rgba_pixels.len };

    const image = sg.makeImage(texture_desc);

    // Store texture and dimensions in the atlas page per spine-c documentation
    if (self) |atlas_page| {
        // we have to dereference the pointer prior to accessing the field because [*c] needs -> to be accessed.
        atlas_page.*.rendererObject = @ptrFromInt(image.id);
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
