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
const MAX_ELEMENT: u64 = 10000;
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
sprite_sheet_view: sg.View = undefined,
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
    defer image.deinit(alloc);

    self.sprite_sheet = sg.makeImage(.{
        .width = @intCast(image.width),
        .height = @intCast(image.height),
        .data = init: {
            var data = sg.ImageData{};
            data.mip_levels[0] = sg.asRange(image.pixels.rgba32);
            break :init data;
        },
    });
    
    self.sprite_sheet_view = sg.makeView(.{
        .texture = .{ .image = self.sprite_sheet },
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
            const animation = spc.spSkeletonData_findAnimation(self.skeleton_data, "hit");
            _ = spc.spAnimationState_setAnimation(state, 0, animation, 0);

            state.*.listener = listener;
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
    to_add.animation_state.rendererObject = @ptrCast(&self.collections[self.current_idx]);

    self.collections[self.current_idx] = to_add;
    self.current_idx += 1;
}

pub export fn listener(
    animation_state: [*c]spc.spAnimationState,
    event_type: spc.spEventType,
    entry: [*c]spc.spTrackEntry,
    event: [*c]spc.spEvent,
) void {
    _ = event;
    const is_looping = entry.*.loop != 0;
    // for now we only care about animation end for things that are not looping
    if (is_looping)
        return;

    const is_ending = event_type == spc.SP_ANIMATION_COMPLETE;
    if (!is_ending)
        return;

    const c_str_name = entry.*.animation.*.name;
    const animation_name: []const u8 = std.mem.span(c_str_name);
    if (!std.mem.eql(u8, animation_name, "hit"))
        return;

    const alien: *Alien = @ptrCast(@alignCast(animation_state.*.rendererObject));
    alien.in_transition = false;

    const run = spc.spSkeletonData_findAnimation(alien.skeleton.*.data, "run");
    _ = spc.spAnimationState_setAnimation(animation_state, 0, run, 1);
}

pub fn update(self: *@This(), dt: f32) RenderableError!void {
    _ = dt;
    for (0..self.current_idx) |i| {
        self.collections[i].update();
    }
}

pub fn render(self: *const @This()) RenderableError!void {
    for (0..self.current_idx) |i| {
        self.collections[i].render(self.sprite_sheet_view, self.pip, self.sampler) catch |e| {
            std.log.err("Error encountered while rendering alien instance: {any}", .{e});
            return RenderableError.RenderError;
        };
    }
}

pub fn deinit(self: *@This()) void {
    sg.destroyView(self.sprite_sheet_view);
    sg.destroyImage(self.sprite_sheet);
    sg.destroySampler(self.sampler);
    sg.destroyPipeline(self.pip);
    self.alloc.destroy(self);
}

pub fn inputEventHandle(self: *@This(), event: [*c]const Event) RenderableError!void {
    // we'll update everything here for now
    switch (event.*.type) {
        .KEY_DOWN => {
            const key_pressed = event.*.key_code;
            var dxy: ?[2]f32 = null;

            switch (key_pressed) {
                .S, .LEFT => {
                    dxy = .{ -1, 0 };
                },
                .D, .DOWN => {
                    dxy = .{ 0, -1 };
                },
                .E, .UP => {
                    dxy = .{ 0, 1 };
                },
                .F, .RIGHT => {
                    dxy = .{ 1, 0 };
                },
                .SPACE => {
                    const init_x = std.crypto.random.float(f32) * 800.0 - 400.0;
                    const init_y = std.crypto.random.float(f32) * 600.0 - 300.0;

                    self.add_instance(init_x, init_y) catch {
                        return RenderableError.RenderError;
                    };
                },
                .BACKSPACE => {
                    if (self.current_idx > 0) {
                        self.current_idx -= 1;
                        const to_remove = &self.collections[self.current_idx];
                        to_remove.deinit();
                    }
                },
                else => {},
            }

            if (dxy) |dxy_| {
                const dx = dxy_[0];
                const dy = dxy_[1];

                for (0..self.current_idx) |i| {
                    const to_render = &self.collections[i];

                    if (to_render.in_transition) {
                        continue;
                    }

                    to_render.should_animate = true;
                    to_render.skeleton.x += dx;
                    to_render.skeleton.y += dy;

                    if (dx > 0) {
                        to_render.skeleton.scaleX = 1.0;
                    } else {
                        to_render.skeleton.scaleX = -1.0;
                    }
                }
            }
        },
        .KEY_UP => {
            for (0..self.current_idx) |i| {
                const alien = &self.collections[i];
                if (!alien.in_transition) {
                    self.collections[i].should_animate = false;
                }
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
    should_animate: bool = true,
    in_transition: bool = true,

    pub fn update(self: *Alien) void {
        util.update(self);
    }

    pub fn render(
        self: Alien,
        texture_view: sg.View,
        pip: sg.Pipeline,
        sampler: sg.Sampler,
    ) !void {
        util.render(self, texture_view, pip, sampler);
    }

    pub fn deinit(self: Alien) void {
        sg.destroyBuffer(self.vertex_buffer);
        sg.destroyBuffer(self.index_buffer);
        spc.spSkeleton_dispose(self.skeleton);
        spc.spAnimationState_dispose(self.animation_state);
    }
};
