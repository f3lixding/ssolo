const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const shd = @import("shaders/cursor.glsl.zig");
const util = @import("util.zig");
const Vertex = util.Vertex;
const assets = @import("assets");
const zigimg = @import("zigimg");
const Event = @import("sokol").app.Event;
const RenderableError = @import("Renderable.zig").RenderableError;
const WINDOW_HEIGHT = @import("main.zig").WINDOW_HEIGHT;
const WINDOW_WIDTH = @import("main.zig").WINDOW_WIDTH;

const ButtonState = enum {
    Idle,
    Left,
    Right,
};

const ImageBundle = struct {
    image: sg.Image,
    height: i32,
    width: i32,
};

idle_image: ImageBundle = undefined,
left_click_image: ImageBundle = undefined,
right_click_image: ImageBundle = undefined,
mx: f32 = 0.0,
my: f32 = 0.0,
y_invert: bool = false,
x_invert: bool = false,
button_state: ButtonState = .Idle,
sampler: sg.Sampler = undefined,
pip: sg.Pipeline = undefined,
vertex_buffer: sg.Buffer = undefined,
index_buffer: sg.Buffer = undefined,
vertices: [6]Vertex = undefined,
alloc: std.mem.Allocator = undefined,

pub fn init(self: *@This(), alloc: std.mem.Allocator) RenderableError!void {
    self.alloc = alloc;

    {
        const image_buffer = assets.cursor_default_png;
        var image = zigimg.Image.fromMemory(alloc, image_buffer) catch {
            std.log.err("Erroring reading image for cursor init", .{});
            return RenderableError.InitError;
        };
        defer image.deinit();

        const sg_image = sg.makeImage(.{
            .width = @intCast(image.height),
            .height = @intCast(image.width),
            .data = init: {
                var data = sg.ImageData{};
                data.subimage[0][0] = sg.asRange(image.pixels.rgba32);
                break :init data;
            },
        });

        self.idle_image = .{
            .image = sg_image,
            .height = @intCast(image.height),
            .width = @intCast(image.width),
        };
    }

    {
        const image_buffer = assets.cursor_default_friends_png;
        var image = zigimg.Image.fromMemory(alloc, image_buffer) catch {
            std.log.err("Erroring reading image for cursor init", .{});
            return RenderableError.InitError;
        };
        defer image.deinit();

        const sg_image = sg.makeImage(.{
            .width = @intCast(image.height),
            .height = @intCast(image.width),
            .data = init: {
                var data = sg.ImageData{};
                data.subimage[0][0] = sg.asRange(image.pixels.rgba32);
                break :init data;
            },
        });

        self.left_click_image = .{
            .image = sg_image,
            .height = @intCast(image.height),
            .width = @intCast(image.width),
        };
    }

    {
        const image_buffer = assets.cursor_pickaxe_red_png;
        var image = zigimg.Image.fromMemory(alloc, image_buffer) catch {
            std.log.err("Erroring reading image for cursor init", .{});
            return RenderableError.InitError;
        };
        defer image.deinit();

        const sg_image = sg.makeImage(.{
            .width = @intCast(image.height),
            .height = @intCast(image.width),
            .data = init: {
                var data = sg.ImageData{};
                data.subimage[0][0] = sg.asRange(image.pixels.rgba32);
                break :init data;
            },
        });

        self.right_click_image = .{
            .image = sg_image,
            .height = @intCast(image.height),
            .width = @intCast(image.width),
        };
    }

    self.pip = util.makePipeline(shd.cursorShaderDesc(sg.queryBackend()));
    self.sampler = sg.makeSampler(.{});

    self.vertex_buffer = sg.makeBuffer(.{
        .usage = .{ .dynamic_update = true },
        .size = @sizeOf(Vertex) * 4,
    });

    self.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true },
        .data = sg.asRange(&[_]u16{
            0, 1, 2, 0, 2, 3,
        }),
    });
}

pub fn render(self: *const @This()) void {
    const current_img = current_img: {
        switch (self.button_state) {
            .Left => break :current_img &self.left_click_image,
            .Right => break :current_img &self.right_click_image,
            else => break :current_img &self.idle_image,
        }
    };

    const half_w = @as(f32, @floatFromInt(current_img.width)) / 2.0;
    const half_h = @as(f32, @floatFromInt(current_img.height)) / 2.0;

    const vertices = [_]Vertex{
        // zig fmt: off
        .{ .x = self.mx - half_w, .y = self.my - half_h, .color = 0xFFFFFFFF, .u = 0.0, .v = 0.0 },
        .{ .x = self.mx - half_w, .y = self.my + half_h, .color = 0xFFFFFFFF, .u = 0.0, .v = 1.0 },
        .{ .x = self.mx + half_w, .y = self.my + half_h, .color = 0xFFFFFFFF, .u = 1.0, .v = 1.0 },
        .{ .x = self.mx + half_w, .y = self.my - half_h, .color = 0xFFFFFFFF, .u = 1.0, .v = 0.0 },
        // zig fmt: on
    };

    sg.updateBuffer(self.vertex_buffer, sg.asRange(vertices[0..]));

    // Create orthographic projection matrix for screen coordinates (0,0 top-left to width,height bottom-right)
    const window_width: f32 = @floatFromInt(WINDOW_WIDTH);
    const window_height: f32 = @floatFromInt(WINDOW_HEIGHT);
    const ortho_matrix = [16]f32{
        2.0 / window_width,  0.0,                 0.0, -1.0,
        0.0,                 -2.0 / window_height, 0.0, 1.0,
        0.0,                 0.0,                 1.0, 0.0,
        0.0,                 0.0,                 0.0, 1.0,
    };
    
    const vs_params = shd.VsParams{
        .mvp = ortho_matrix,
    };

    const bind = sg.Bindings{
        .vertex_buffers = ver: {
            var buffers = [_]sg.Buffer{.{}} ** 8;
            buffers[0] = self.vertex_buffer;
            break :ver buffers;
        },
        .index_buffer = self.index_buffer,
        .images = image: {
            var images = [_]sg.Image{.{}} ** 16;
            images[shd.IMG_tex] = current_img.image;
            break :image images;
        },
        .samplers = smp: {
            var samplers = [_]sg.Sampler{.{}} ** 16;
            samplers[shd.SMP_smp] = self.sampler;
            break :smp samplers;
        },
    };

    sg.applyPipeline(self.pip);
    sg.applyBindings(bind);
    sg.applyUniforms(shd.UB_vs_params, sg.asRange(&vs_params));
    sg.draw(0, 6, 1);
}

pub fn inputEventHandle(self: *@This(), event: [*c]const Event) RenderableError!void {
    switch (event.*.type) {
        .MOUSE_MOVE => {
            self.mx = event.*.mouse_x;
            self.my = event.*.mouse_y;
        },
        .MOUSE_DOWN => {
            // TODO: account for when multiple mouse buttons are pressed
            switch (event.*.mouse_button) {
                .LEFT => self.button_state = .Left,
                .RIGHT => self.button_state = .Right,
                else => {},
            }
        },
        .MOUSE_UP => {
            // TODO: account for when multiple mouse buttons are pressed
            self.button_state = .Idle;
        },
        else => {},
    }
}

pub fn update(_: *@This(), _: f32) RenderableError!void {}

pub fn deinit(self: *@This()) void {
    sg.destroyImage(self.idle_image.image);
    sg.destroyImage(self.left_click_image.image);
    sg.destroyImage(self.right_click_image.image);
    sg.destroySampler(self.sampler);
    sg.destroyBuffer(self.vertex_buffer);
    sg.destroyBuffer(self.index_buffer);

    self.alloc.destroy(self);
}
