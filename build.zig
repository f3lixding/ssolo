const std = @import("std");

// TODO: we can structure the folder in such a way that we can crawl for this list
const ENTITY_NAMES = [_][]const u8{
    "alien-ess",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const no_bin = b.option(bool, "no-bin", "skip emitting binary") orelse false;

    const bin_to_add = b.addExecutable(.{
        .name = "ssolo",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("src/main.zig"),
    });

    const spine_c_lib = b.dependency("spine_c", .{
        .target = target,
        .optimize = optimize,
    });

    const sokol_dep = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const zigimg_dep = b.dependency("zigimg", .{
        .target = target,
        .optimize = optimize,
    });

    bin_to_add.linkLibrary(spine_c_lib.artifact("spine-c"));
    bin_to_add.addIncludePath(spine_c_lib.path("include"));
    bin_to_add.root_module.addImport("sokol", sokol_dep.module("sokol"));
    bin_to_add.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));

    if (!no_bin) {
        b.installArtifact(bin_to_add);
    } else {
        b.getInstallStep().dependOn(&bin_to_add.step);
    }

    // run step
    const run_main = b.addRunArtifact(bin_to_add);
    b.step("run", "run main app").dependOn(&run_main.step);

    // building of shader files
    // TODO: scan for file metadata to see if they need to be run
    for (ENTITY_NAMES) |name| {
        const shdc = run_sokol_shdc(b, name);
        bin_to_add.step.dependOn(&shdc.step);
    }
}

pub fn run_sokol_shdc(
    b: *std.Build,
    name: []const u8,
) *std.Build.Step.Run {
    const sokol_shdc = b.addSystemCommand(&.{
        "sokol-shdc",
        "-i",
        b.fmt("src/shaders/{s}.glsl", .{name}),
        "-o",
        b.fmt("src/shaders/{s}.glsl.zig", .{name}),
        "-l",
        "glsl410:glsl300es:hlsl5:metal_macos:wgsl",
        "-f",
        "sokol_zig",
    });

    return sokol_shdc;
}
