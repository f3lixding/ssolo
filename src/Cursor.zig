const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const shd = @import("shaders/cursor.glsl.zig");
const Vertex = @import("util.zig").Vertex;
const assets = @import("assets");
const zigimg = @import("zigimg");
const Event = @import("sokol").app.Event;
const RenderableError = @import("Renderable.zig").RenderableError;

const ButtonState = enum {
    Idle,
    Left,
    Right,
};

const ImageBundle = struct {
    image: sg.Image,
    view: sg.View,
    height: i32,
    width: i32,
};

idle_image: ImageBundle = undefined,
left_click_image: ImageBundle = undefined,
right_click_image: ImageBundle = undefined,
mx: f32 = 0.0,
my: f32 = 0.0,
y_invert: bool = true,
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
        const image_buffer: []const u8 = assets.cursor_default_png;
        var image = zigimg.Image.fromMemory(alloc, image_buffer) catch {
            std.log.err("Erroring reading image for cursor init", .{});
            return RenderableError.InitError;
        };
        defer image.deinit(self.alloc);

        const sg_image = sg.makeImage(.{
            .width = @intCast(image.width),
            .height = @intCast(image.height),
            .data = init: {
                var data = sg.ImageData{};
                data.mip_levels[0] = sg.asRange(image.pixels.rgba32);
                break :init data;
            },
        });

        self.idle_image = .{
            .image = sg_image,
            .view = sg.makeView(.{
                .texture = .{ .image = sg_image },
            }),
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
        defer image.deinit(self.alloc);

        const sg_image = sg.makeImage(.{
            .width = @intCast(image.width),
            .height = @intCast(image.height),
            .data = init: {
                var data = sg.ImageData{};
                data.mip_levels[0] = sg.asRange(image.pixels.rgba32);
                break :init data;
            },
        });

        self.left_click_image = .{
            .image = sg_image,
            .view = sg.makeView(.{
                .texture = .{ .image = sg_image },
            }),
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
        defer image.deinit(self.alloc);

        const sg_image = sg.makeImage(.{
            .width = @intCast(image.width),
            .height = @intCast(image.height),
            .data = init: {
                var data = sg.ImageData{};
                data.mip_levels[0] = sg.asRange(image.pixels.rgba32);
                break :init data;
            },
        });

        self.right_click_image = .{
            .image = sg_image,
            .view = sg.makeView(.{
                .texture = .{ .image = sg_image },
            }),
            .height = @intCast(image.height),
            .width = @intCast(image.width),
        };
    }

    self.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.cursorShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_cursor_pos].format = .FLOAT2;
            l.attrs[shd.ATTR_cursor_uv0].format = .FLOAT2;
            l.attrs[shd.ATTR_cursor_color0].format = .UBYTE4N;
            break :init l;
        },
        .index_type = .UINT16,
        .depth = .{
            .compare = .ALWAYS,
            .write_enabled = false,
        },
        .cull_mode = .NONE,
        .colors = init: {
            var colors: [4]sg.ColorTargetState = undefined;
            var color = sg.ColorTargetState{};
            color.blend = .{
                .enabled = true,
                .src_factor_rgb = .SRC_ALPHA,
                .dst_factor_rgb = .ONE_MINUS_SRC_ALPHA,
                .src_factor_alpha = .ONE,
                .dst_factor_alpha = .ONE_MINUS_SRC_ALPHA,
            };
            colors[0] = color;
            break :init colors;
        },
    });
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

    // Reminder that the vertex buffer has a min of -1.0 and a max of 1.0 for both axis
    // Thus you would need to normalize it
    const current_width: f32 = @floatFromInt(sokol.app.width());
    const current_height: f32 = @floatFromInt(sokol.app.height());
    const img_height = @as(f32, @floatFromInt(current_img.height));
    const img_width = @as(f32, @floatFromInt(current_img.width));
    const nh: f32 = img_height / current_height;
    const nw: f32 = img_width / current_width;

    const x_invert: f32 = if (self.x_invert) -1.0 else 1.0;
    const y_invert: f32 = if (self.y_invert) -1.0 else 1.0;
    const nx: f32 = x_invert * (self.mx / (current_width * 0.5));
    const ny: f32 = y_invert * (self.my / (current_height * 0.5));

    const vertices = [_]Vertex{
        // zig fmt: off
        .{ .x = nx,      .y = ny,      .color = 0xFFFFFFFF, .u = 0.0, .v = 0.0 }, // top-left
        .{ .x = nx,      .y = ny - nh, .color = 0xFFFFFFFF, .u = 0.0, .v = 1.0 }, // bottom-left  
        .{ .x = nx + nw, .y = ny - nh, .color = 0xFFFFFFFF, .u = 1.0, .v = 1.0 }, // bottom-right
        .{ .x = nx + nw, .y = ny,      .color = 0xFFFFFFFF, .u = 1.0, .v = 0.0 }, // top-right
        // zig fmt: on
    };

    sg.updateBuffer(self.vertex_buffer, sg.asRange(vertices[0..]));

    const bind = sg.Bindings{
        .vertex_buffers = ver: {
            var buffers = [_]sg.Buffer{.{}} ** 8;
            buffers[0] = self.vertex_buffer;
            break :ver buffers;
        },
        .index_buffer = self.index_buffer,
        .views = views: {
            var views_array = [_]sg.View{.{}} ** 28;
            views_array[shd.VIEW_tex] = current_img.view;
            break :views views_array;
        },
        .samplers = smp: {
            var samplers = [_]sg.Sampler{.{}} ** 16;
            samplers[shd.SMP_smp] = self.sampler;
            break :smp samplers;
        },
    };

    sg.applyPipeline(self.pip);
    sg.applyBindings(bind);
    sg.draw(0, 6, 1);
}

pub fn inputEventHandle(self: *@This(), event: [*c]const Event) RenderableError!void {
    switch (event.*.type) {
        .MOUSE_MOVE => {
            const half_w = @as(f32, @floatFromInt(sokol.app.width())) / 2.0;
            const half_h = @as(f32, @floatFromInt(sokol.app.height())) / 2.0;
            const new_x: f32 = self.mx + event.*.mouse_dx;
            const x_mul: f32 = if (new_x >= 0) 1.0 else -1.0;
            const new_y: f32 = self.my + event.*.mouse_dy;
            const y_mul: f32 = if (new_y >= 0) 1.0 else -1.0;

            self.mx = if (@abs(new_x) > half_w) x_mul * half_w else new_x;
            self.my = if (@abs(new_y) > half_h) y_mul * half_h else new_y;
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

pub fn deinit(self: *@This()) void {
    sg.destroyView(self.idle_image.view);
    sg.destroyView(self.left_click_image.view);
    sg.destroyView(self.right_click_image.view);
    sg.destroyImage(self.idle_image.image);
    sg.destroyImage(self.left_click_image.image);
    sg.destroyImage(self.right_click_image.image);
    sg.destroySampler(self.sampler);
    sg.destroyBuffer(self.vertex_buffer);
    sg.destroyBuffer(self.index_buffer);

    self.alloc.destroy(self);
}
