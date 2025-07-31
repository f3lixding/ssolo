const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const sokol = @import("sokol");
const sg = sokol.gfx;
const spc = util.spine_c;
const shd = @import("../shaders/alien_ess.glsl.zig");
const zigimg = @import("zigimg");
const Event = sokol.app.Event;

const Renderable = @import("../Renderable.zig");
const RenderableError = Renderable.RenderableError;
const util = @import("../util.zig");
const Vertex = util.Vertex;
const assets = @import("assets");

const ASSET_FILE_STEM: []const u8 = "alien_ess";
const MAX_ELEMENT: u64 = 100;
const MAX_VERTICES_PER_ATTACHMENT = util.MAX_VERTICES_PER_ATTACHMENT;

const AlienError = error{Full};

// we'll use a predetermined length for now
// in the future we shall perhaps make this struct a generic that takes this in as a parameter
collections: [MAX_ELEMENT]Alien = undefined,
alloc: std.mem.Allocator = undefined,
current_idx: usize = 0,
skeleton_data: *spc.struct_spSkeletonData = undefined,
animation_state_data: *spc.struct_spAnimationStateData = undefined,
sprite_sheet: sg.Image = undefined,
sampler: sg.Sampler = undefined,
shader: sg.Shader = undefined,
pip: sg.Pipeline = undefined,

pub fn init(self: *@This(), alloc: Allocator) RenderableError!void {
    const init_bundle = util.getInitBundle(
        ASSET_FILE_STEM,
        0.5,
        0.2,
    ) catch |e| {
        std.log.err("Error creating init bundle for {s}: {any}", .{ ASSET_FILE_STEM, e });
        return RenderableError.InitError;
    };

    const image_buffer = comptime blk: {
        break :blk @field(assets, std.fmt.comptimePrint("{s}_png", .{ASSET_FILE_STEM}));
    };
    var image = zigimg.Image.fromMemory(alloc, image_buffer) catch {
        return RenderableError.InitError;
    };
    defer image.deinit();

    self.sprite_sheet = sg.makeImage(.{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .data = init: {
            var data = sg.ImageData{};
            data.subimage[0][0] = sg.asRange(image.pixels.rgba32);
            break :init data;
        },
    });

    self.skeleton_data = init_bundle.skeleton_data;
    self.animation_state_data = init_bundle.animation_state_data;

    self.pip = util.makePipeline(shd.alienEssShaderDesc(sg.queryBackend()));

    self.sampler = sg.makeSampler(.{});

    // We default to having one instance for now:
    self.add_instance(0.0, 0.0) catch |e| {
        switch (e) {
            error.Full => {
                std.log.info("Alien collections are full. Cannot add anymore", .{});
            },
        }
    };

    self.alloc = alloc;
}

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

pub fn deinit(self: *@This()) void {
    self.alloc.destroy(self);
}

pub fn inputEventHandle(self: *@This(), event: [*c]const Event) RenderableError!void {
    // we'll update everything here for now
    switch (event.*.type) {
        .KEY_DOWN => {
            const key_pressed = event.*.key_code;
            // TODO: account for diagonals
            const dxy: ?[2]f32 = blk: {
                switch (key_pressed) {
                    .S, .LEFT => break :blk .{ -1, 0 },
                    .D, .DOWN => break :blk .{ 0, -1 },
                    .E, .UP => break :blk .{ 0, 1 },
                    .F, .RIGHT => break :blk .{ 1, 0 },
                    else => break :blk null,
                }
            };

            if (dxy) |dxy_| {
                const dx = dxy_[0];
                const dy = dxy_[1];

                for (0..self.current_idx) |i| {
                    // TODO: maybe make this a bit more ergonomic?
                    self.collections[i].should_animate = true;
                    self.collections[i].skeleton.x += dx;
                    self.collections[i].skeleton.y += dy;

                    if (dx > 0) {
                        self.collections[i].skeleton.scaleX = 1.0;
                    } else {
                        self.collections[i].skeleton.scaleX = -1.0;
                    }
                }
            }
        },
        .KEY_UP => {
            for (0..self.current_idx) |i| {
                self.collections[i].should_animate = false;
            }
        },
        else => {
            // ignore everything else for now
        },
    }
}

const Alien = struct {
    skeleton: *spc.spSkeleton,
    animation_state: *spc.spAnimationState,
    vertex_buffer: sg.Buffer,
    index_buffer: sg.Buffer,
    vertices: [MAX_VERTICES_PER_ATTACHMENT]Vertex = undefined,
    total_vertex_count: usize = 0,
    world_vertices_pos: [MAX_VERTICES_PER_ATTACHMENT]f32 = undefined,
    should_animate: bool = false,

    pub fn update(self: *Alien) void {
        util.update(self);
    }

    pub fn render(
        self: Alien,
        texture: *sg.Image,
        pip: sg.Pipeline,
        sampler: sg.Sampler,
    ) !void {
        util.render(self, texture, pip, sampler);
    }
};
