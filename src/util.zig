const std = @import("std");
const Allocator = std.mem.Allocator;

const spine_c = @cImport({
    @cInclude("spine/spine.h");
    @cInclude("spine/extension.h");
});

const LoadAnimationError = error{
    NullSkeleton,
};

pub fn loadAnimationData(
    alloc: Allocator,
    path: []const u8,
    animation_mix: std.StringHashMap(
        []struct { []const u8, []const u8 },
    ),
) !void {
    const atlas = spine_c.spAtlas_createFromFile(@ptrCast(path), null);
    const binary = spine_c.spSkeletonBinary_create(atlas);
    defer spine_c.spSkeletonBinary_dispose(binary);
    binary.*.scale = 1;

    // We are going to assume the .skel file name is the same as the atlas file name
    const skel_path = dir: {
        const file_name = std.fs.path.stem(path);
        const dir_name = std.fs.path.dirname(path).?;
        break :dir std.fmt.allocPrint(alloc, "{s}/{s}.skel", .{ dir_name, file_name });
    } catch unreachable;
    const skeleton_data = spine_c.spSkeletonBinary_readSkeletonDataFile(binary, @ptrCast(skel_path));

    if (skeleton_data == null) {
        try std.io.getStdErr().writer().print("Received null for skeleton data\n", .{});
        return LoadAnimationError.NullSkeleton;
    }

    // Prep animation state data
    const animation_state_data = spine_c.spAnimationStateData_create(skeleton_data);
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
