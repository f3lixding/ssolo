const std = @import("std");
const Build = std.Build;

pub fn build(b: *Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = b.addLibrary(.{
        .name = "spine-c",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Add include directories (adjust based on spine-c structure)
    lib.addIncludePath(b.path("include")); // or wherever headers are
    lib.linkLibC();
    lib.addCSourceFiles(.{
        .files = src,
    });

    if (target.result.os.tag != .windows) {
        lib.linkSystemLibrary("m");
    }

    b.installArtifact(lib);
}

const src: []const []const u8 = &.{
    "src/spine/Animation.c",
    "src/spine/AnimationState.c",
    "src/spine/AnimationStateData.c",
    "src/spine/Array.c",
    "src/spine/Atlas.c",
    "src/spine/AtlasAttachmentLoader.c",
    "src/spine/Attachment.c",
    "src/spine/AttachmentLoader.c",
    "src/spine/Bone.c",
    "src/spine/BoneData.c",
    "src/spine/BoundingBoxAttachment.c",
    "src/spine/ClippingAttachment.c",
    "src/spine/Color.c",
    "src/spine/Debug.c",
    "src/spine/Event.c",
    "src/spine/EventData.c",
    "src/spine/extension.c",
    "src/spine/IkConstraint.c",
    "src/spine/IkConstraintData.c",
    "src/spine/Json.c",
    "src/spine/MeshAttachment.c",
    "src/spine/PathAttachment.c",
    "src/spine/PathConstraint.c",
    "src/spine/PathConstraintData.c",
    "src/spine/PhysicsConstraint.c",
    "src/spine/PhysicsConstraintData.c",
    "src/spine/PointAttachment.c",
    "src/spine/RegionAttachment.c",
    "src/spine/Sequence.c",
    "src/spine/Skeleton.c",
    "src/spine/SkeletonBinary.c",
    "src/spine/SkeletonBounds.c",
    "src/spine/SkeletonClipping.c",
    "src/spine/SkeletonData.c",
    "src/spine/SkeletonJson.c",
    "src/spine/Skin.c",
    "src/spine/Slot.c",
    "src/spine/SlotData.c",
    "src/spine/TransformConstraint.c",
    "src/spine/TransformConstraintData.c",
    "src/spine/Triangulator.c",
    "src/spine/VertexAttachment.c",
};
