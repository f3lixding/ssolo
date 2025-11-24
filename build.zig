const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const no_bin = b.option(bool, "no-bin", "skip emitting binary") orelse false;
    const force_codegen = b.option(bool, "force-codegen", "force code gen") orelse false;

    const bin_to_add = b.addExecutable(.{
        .name = "ssolo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    generate_asset_files(b, force_codegen) catch unreachable;
    run_sokol_shdc(b, &bin_to_add.step, force_codegen) catch unreachable;

    bin_to_add.root_module.addAnonymousImport("assets", .{
        .root_source_file = b.path("assets/assets.zig"),
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

    const pda_dep = b.dependency("pda", .{
        .target = target,
        .optimize = optimize,
    });

    const test_filter = b.option([]const u8, "filter", "filter for a test");
    const build_unit_tests = b.addTest(.{
        .name = "Test entry point",
        .root_module = b.createModule(.{
            .root_source_file = b.path("test_main.zig"),
            .target = target,
            .optimize = std.builtin.OptimizeMode.Debug,
        }),
        .filters = if (test_filter) |filter| &.{filter} else &.{},
    });
    build_unit_tests.linkLibC();
    build_unit_tests.linkLibrary(spine_c_lib.artifact("spine-c"));
    build_unit_tests.addIncludePath(spine_c_lib.path("include"));
    build_unit_tests.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));
    build_unit_tests.root_module.addImport("sokol", sokol_dep.module("sokol"));

    const util_test_step = b.step("test", "Run util unit test");
    const run_util_test = b.addRunArtifact(build_unit_tests);
    util_test_step.dependOn(&run_util_test.step);

    bin_to_add.linkLibrary(spine_c_lib.artifact("spine-c"));
    bin_to_add.addIncludePath(spine_c_lib.path("include"));
    bin_to_add.root_module.addImport("sokol", sokol_dep.module("sokol"));
    bin_to_add.root_module.addImport("zigimg", zigimg_dep.module("zigimg"));
    bin_to_add.root_module.addImport("pda", pda_dep.module("pda"));

    bin_to_add.linkSystemLibrary("GL");
    bin_to_add.linkSystemLibrary("X11");
    bin_to_add.linkSystemLibrary("Xi");
    bin_to_add.linkSystemLibrary("Xcursor");
    bin_to_add.linkSystemLibrary("asound");

    if (!no_bin) {
        b.installArtifact(bin_to_add);
    } else {
        b.getInstallStep().dependOn(&bin_to_add.step);
    }

    // run step
    const run_main = b.addRunArtifact(bin_to_add);
    b.step("run", "run main app").dependOn(&run_main.step);
}

pub fn run_sokol_shdc(
    b: *std.Build,
    bin_step: *std.Build.Step,
    force_codegen: bool,
) !void {
    const shaders_dir = try std.fs.cwd().openDir("src/shaders", .{ .iterate = true });
    var walker = try shaders_dir.walk(b.allocator);
    defer walker.deinit();

    // [0]: .glsl mtime
    // [1]: .zig mtime
    var mtime_map = std.StringHashMap([2]i128).init(b.allocator);
    defer mtime_map.deinit();

    while (try walker.next()) |entry| {
        const file_ext = std.fs.path.extension(entry.path);
        const file_name = try b.allocator.dupe(u8, std.fs.path.stem(entry.path));

        const lookup_key = key: {
            if (std.mem.eql(u8, ".glsl", file_ext)) {
                break :key file_name;
            } else if (std.mem.eql(u8, ".zig", file_ext)) {
                break :key file_name[0 .. file_name.len - ".glsl".len];
            } else {
                unreachable;
            }
        };

        if (mtime_map.getPtr(lookup_key)) |mtimes| {
            if (std.mem.eql(u8, ".glsl", file_ext)) {
                mtimes[0] = (try shaders_dir.statFile(entry.path)).mtime;
            } else {
                mtimes[1] = (try shaders_dir.statFile(entry.path)).mtime;
            }
        } else {
            var mtime: [2]i128 = .{ std.math.maxInt(i128), std.math.maxInt(i128) };
            if (std.mem.eql(u8, ".glsl", file_ext)) {
                mtime[0] = (try shaders_dir.statFile(entry.path)).mtime;
            } else {
                mtime[1] = (try shaders_dir.statFile(entry.path)).mtime;
            }
            try mtime_map.put(lookup_key, mtime);
        }
    }

    var mtime_map_iter = mtime_map.iterator();
    while (mtime_map_iter.next()) |entry| {
        const glsl_mtime = entry.value_ptr[0];
        const zig_mtime = entry.value_ptr[1];

        if (force_codegen or glsl_mtime > zig_mtime) {
            const name = entry.key_ptr.*;
            std.log.info("Running shaders codegen for {s}", .{name});

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

            bin_step.dependOn(&sokol_shdc.step);
        }
    }
}

fn generate_asset_files(b: *std.Build, force_codegen: bool) !void {
    // first we need to scan the time stamps of the asset files
    var assets_dir = try std.fs.cwd().openDir("assets", .{ .iterate = true });

    const should_proceed = should_run: {
        if (force_codegen) {
            break :should_run force_codegen;
        }

        const assets_module_mtime = (try assets_dir.statFile("assets.zig")).mtime;
        const latest_asset_mtime = date: {
            var latest: i128 = 0;
            var iterator = assets_dir.iterate();

            while (try iterator.next()) |file| {
                if (std.mem.eql(u8, "assets.zig", file.name)) {
                    continue;
                }
                const stat = try assets_dir.statFile(file.name);
                latest = @max(latest, stat.mtime);
            }

            break :date latest;
        };

        break :should_run latest_asset_mtime < assets_module_mtime;
    };

    if (!should_proceed) {
        assets_dir.close();
        return;
    }

    // We expect the assets to be named in the following ways:
    // - {asset_name}.atlas
    // - {asset_name}.png
    // - {asset_name}.skel
    // And we are also going to ignore anything that is suffixed with .zig in this folder
    // We are also going to assume there are no folder in this directory

    // This is a hashmap of K: asset name, ane values are array of Strings we are going to write
    // The strings are assumed to end with new lines (so there is no need to append new lines after)
    var asset_map = std.StringHashMap(std.ArrayList([]const u8)).init(b.allocator);
    defer {
        var iterator = asset_map.iterator();
        const alloc = asset_map.allocator;
        while (iterator.next()) |entry| {
            entry.value_ptr.*.deinit(alloc);
        }
        asset_map.deinit();
    }
    var walker = try assets_dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const file_ext = std.fs.path.extension(entry.path);
        if (std.mem.eql(u8, ".zig", file_ext)) {
            continue;
        }

        // We need to dupe it here because [std.fs.path.stem] only returns the pointer
        // Reminder that the key of the hashmap isn't actually of type String (there is no string type in zig)
        // You are literally just storing a fat pointer
        const file_name = try b.allocator.dupe(u8, std.fs.path.stem(entry.basename));
        if (asset_map.getPtr(file_name)) |collection| {
            // Note that we are assuming the names are valid variable names
            // They cannot be kebab case
            const file_ext_with_no_dot = file_ext[1..];
            const alloc = asset_map.allocator;
            try collection.append(alloc, b.fmt(
                "pub const {s}_{s} = @embedFile(\"{s}\");\n",
                .{
                    file_name,
                    file_ext_with_no_dot,
                    entry.basename,
                },
            ));
        } else {
            var collection: std.ArrayList([]const u8) = .empty;
            const file_ext_with_no_dot = file_ext[1..];
            try collection.append(b.allocator, b.fmt(
                "pub const {s}_{s} = @embedFile(\"{s}\");\n",
                .{
                    file_name,
                    file_ext_with_no_dot,
                    entry.basename,
                },
            ));
            try asset_map.put(file_name, collection);
        }
    }

    // Now we iterate through our map to write it to file
    var content: []const u8 =
        \\// THIS FILE IS GENERETED WITH BUILD SCRIPT
        \\// DO NOT EDIT
        \\
    ;
    var asset_map_iter = asset_map.iterator();
    while (asset_map_iter.next()) |entry| {
        const collection = entry.value_ptr.*;
        const joined = try std.mem.join(b.allocator, "", collection.items);
        content = b.fmt("{s}\n{s}", .{ content, joined });
    }

    try assets_dir.writeFile(.{
        .sub_path = "assets.zig",
        .data = content,
    });
}
