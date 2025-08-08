const std = @import("std");
const sokol = @import("sokol");
const sg = sokol.gfx;
const shd = @import("shaders/alien_ess.glsl.zig");
const util = @import("util.zig");
const Vertex = util.Vertex;

pub const Cursor = struct {
    image: sg.Image = undefined,
    sampler: sg.Sampler = undefined,
    pip: sg.Pipeline = undefined,
    vertex_buffer: sg.Buffer = undefined,
    index_buffer: sg.Buffer = undefined,
    vertices: [6]Vertex = undefined,

    pub fn init(self: *Cursor, _: std.mem.Allocator) !void {
        // create a tiny 16x16 pixel-art pickaxe (RGBA)
        const w: usize = 16;
        const h: usize = 16;
        var pixels: [w * h * 4]u8 = undefined;
        // fully transparent background
        for (pixels[0..]) |*p| p.* = 0;

        // simple pickaxe: grey head and brown handle (very minimal)
        const GREY: [4]u8 = .{0xCC, 0xCC, 0xCC, 0xFF};
        const BROWN: [4]u8 = .{0x8B, 0x5A, 0x2B, 0xFF};

        // draw a small head (rows 4..7, cols 8..13)
        for (4..8) |row| {
            for (8..14) |col| {
                const idx = (row * w + col) * 4;
                pixels[idx + 0] = GREY[0];
                pixels[idx + 1] = GREY[1];
                pixels[idx + 2] = GREY[2];
                pixels[idx + 3] = GREY[3];
            }
        }

        // draw a diagonal brown handle
        var r: usize = 9;
        var c: usize = 3;
        while (r < 15 and c < 12) : ({ r += 1; c += 1; }) {
            const idx = (r * w + c) * 4;
            pixels[idx + 0] = BROWN[0];
            pixels[idx + 1] = BROWN[1];
            pixels[idx + 2] = BROWN[2];
            pixels[idx + 3] = BROWN[3];
        }

        self.image = sg.makeImage(.{
            .width = @intCast(w),
            .height = @intCast(h),
            .data = init: {
                var d = sg.ImageData{};
                d.subimage[0][0] = sg.asRange(pixels[0..]);
                break :init d;
            },
        });

        self.pip = util.makePipeline(shd.alienEssShaderDesc(sg.queryBackend()));
        self.sampler = sg.makeSampler(.{});

        self.vertex_buffer = sg.makeBuffer(.{
            .usage = .{ .dynamic_update = true },
            .size = @sizeOf(Vertex) * 6,
        });

        self.index_buffer = sg.makeBuffer(.{
            .usage = .{ .index_buffer = true, .dynamic_update = true },
            .size = @sizeOf(u16) * 6,
        });
    }

    pub fn render(self: *const Cursor) void {
        // cursor should follow the latest mouse position captured in util
        const mx = util.mouse_x;
        const my = util.mouse_y;

        // sprite size in pixels
        const sw: f32 = 16.0;
        const sh: f32 = 16.0;

        // convert to normalized device coords used elsewhere (800x600 hardcoded convention)
        const left = mx - sw * 0.5;
        const right = mx + sw * 0.5;
        const top = my - sh * 0.5;
        const bottom = my + sh * 0.5;

        const nx_left = left / 400.0;
        const nx_right = right / 400.0;
        const ny_top = top / 300.0;
        const ny_bottom = bottom / 300.0;

        const white: u32 = 0xFFFFFFFF;

        // v0 v1 v2 | v2 v3 v0 mapping like util.addVertex expects
        var verts: [6]Vertex = .{
            Vertex{ .x = nx_left, .y = ny_top, .u = 0.0, .v = 0.0, .color = white },
            Vertex{ .x = nx_right, .y = ny_top, .u = 1.0, .v = 0.0, .color = white },
            Vertex{ .x = nx_right, .y = ny_bottom, .u = 1.0, .v = 1.0, .color = white },
            Vertex{ .x = nx_right, .y = ny_bottom, .u = 1.0, .v = 1.0, .color = white },
            Vertex{ .x = nx_left, .y = ny_bottom, .u = 0.0, .v = 1.0, .color = white },
            Vertex{ .x = nx_left, .y = ny_top, .u = 0.0, .v = 0.0, .color = white },
        };

        sg.updateBuffer(self.vertex_buffer, sg.asRange(verts[0..]));

        var indices: [6]u16 = .{0,1,2,3,4,5};
        sg.updateBuffer(self.index_buffer, sg.asRange(indices[0..]));

        const bind = sg.Bindings{
            .vertex_buffers = ver: {
                var buffers = [_]sg.Buffer{.{}} ** 8;
                buffers[0] = self.vertex_buffer;
                break :ver buffers;
            },
            .index_buffer = self.index_buffer,
            .images = image: {
                var images = [_]sg.Image{.{}} ** 16;
                images[shd.IMG_tex] = self.image;
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
        sg.draw(0, 6, 1);
    }

    pub fn deinit(self: *Cursor) void {
        sg.destroyImage(self.image);
        sg.destroySampler(self.sampler);
        sg.destroyBuffer(self.vertex_buffer);
        sg.destroyBuffer(self.index_buffer);
    }
};
