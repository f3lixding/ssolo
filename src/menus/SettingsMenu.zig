//! Core type for settings menu
//! This is the first page of the menu and it should show the following
//! - Control mapping
//! - Video settings
//! - Audio settings
const std = @import("std");
const Allocator = std.mem.Allocator;

const Pda = @import("pda").Pda;
const Widget = @import("widget.zig").Widget;
const Event = @import("sokol").app.Event;
const sokol = @import("sokol");
const sg = sokol.gfx;
const sapp = sokol.app;
const Vertex = @import("../util.zig").Vertex;
const Self = @This();

const SymbolType = enum {
    Esc,
    ControlMappingsClick,
    VideoSettingsClick,
    AudioSettingsClick,
};

const StateType = enum {
    Hidden,
    FirstPage,
    ControlMappings,
    VideoSettings,
    AudioSettings,
};
const PushdownAutomaton = Pda(StateType, SymbolType);

pda: PushdownAutomaton = undefined,
top_left_coord: [2]f32 = undefined,
height: i32 = undefined,
width: i32 = undefined,
alloc: Allocator = undefined,
vertex_buffer: sg.Buffer = undefined,
index_buffer: sg.Buffer = undefined,
pip: sg.Pipeline = undefined,
sampler: sg.Sampler = undefined,

pub fn init(self: *Self, alloc: Allocator, top_left_coord: [2]f32, height: i32, width: i32) !void {
    self.alloc = alloc;
    self.top_left_coord = top_left_coord;
    self.height = height;
    self.width = width;
    self.pda = PushdownAutomaton{
        .alloc = alloc,
        .current_state = .Hidden,
        .stack = .empty,
        .transitionFnPtr = pdaTransitionFn,
    };

    const shd = @import("../shaders/menu.glsl.zig");
    self.pip = sg.makePipeline(.{
        .shader = sg.makeShader(shd.menuShaderDesc(sg.queryBackend())),
        .layout = init: {
            var l = sg.VertexLayoutState{};
            l.attrs[shd.ATTR_menu_pos].format = .FLOAT2;
            l.attrs[shd.ATTR_menu_uv0].format = .FLOAT2;
            l.attrs[shd.ATTR_menu_color0].format = .UBYTE4N;
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
        .size = @sizeOf(Vertex) * 24,
    });

    self.index_buffer = sg.makeBuffer(.{
        .usage = .{ .index_buffer = true },
        .data = sg.asRange(&[_]u16{
            // First rectangle
            0,  1,  2,  0,  2,  3,
            4,  5,  6,  4,  6,  7,
            // Second rectangle
            8,  9,  10, 8,  10, 11,
            12, 13, 14, 12, 14, 15,
            // Third rectangle
            16, 17, 18, 16, 18, 19,
            20, 21, 22, 20, 22, 23,
        }),
    });
}

pub fn render(self: *const Self) !void {
    if (self.pda.peakCurrentState() == .Hidden) {
        return;
    }

    const current_width: f32 = @floatFromInt(sapp.width());
    const current_height: f32 = @floatFromInt(sapp.height());

    var vertices: [24]Vertex = undefined;

    const bg_vertices = [_]Vertex{
        // zig fmt: off
        .{ .x = -1.0, .y =  1.0, .color = 0xB3000000, .u = 0.0, .v = 0.0 },
        .{ .x = -1.0, .y = -1.0, .color = 0xB3000000, .u = 0.0, .v = 1.0 },
        .{ .x =  1.0, .y = -1.0, .color = 0xB3000000, .u = 1.0, .v = 1.0 },
        .{ .x =  1.0, .y =  1.0, .color = 0xB3000000, .u = 1.0, .v = 0.0 },
        // zig fmt: on
    };

    for (0..4) |i| {
        vertices[i] = bg_vertices[i];
    }

    const title_height = 60.0 / current_height;
    const title_width = 200.0 / current_width;
    const title_y = 0.6;

    const title_vertices = [_]Vertex{
        // zig fmt: off
        .{ .x = -title_width, .y = title_y + title_height, .color = 0xFFFFFFFF, .u = 0.0, .v = 0.0 },
        .{ .x = -title_width, .y = title_y,                .color = 0xFFFFFFFF, .u = 0.0, .v = 1.0 },
        .{ .x =  title_width, .y = title_y,                .color = 0xFFFFFFFF, .u = 1.0, .v = 1.0 },
        .{ .x =  title_width, .y = title_y + title_height, .color = 0xFFFFFFFF, .u = 1.0, .v = 0.0 },
        // zig fmt: on
    };

    for (0..4) |i| {
        vertices[i + 4] = title_vertices[i];
    }

    const button_width = 300.0 / current_width;
    const button_height = 50.0 / current_height;

    const buttons = [_]struct { y_offset: f32 }{
        .{ .y_offset = 0.2 },
        .{ .y_offset = -0.1 },
        .{ .y_offset = -0.4 },
    };

    for (buttons, 0..) |button, i| {
        const base_idx = 8 + i * 4;
        const button_vertices = [_]Vertex{
            // zig fmt: off
            .{ .x = -button_width, .y = button.y_offset + button_height, .color = 0xFF444444, .u = 0.0, .v = 0.0 },
            .{ .x = -button_width, .y = button.y_offset,                 .color = 0xFF444444, .u = 0.0, .v = 1.0 },
            .{ .x =  button_width, .y = button.y_offset,                 .color = 0xFF444444, .u = 1.0, .v = 1.0 },
            .{ .x =  button_width, .y = button.y_offset + button_height, .color = 0xFF444444, .u = 1.0, .v = 0.0 },
            // zig fmt: on
        };

        for (0..4) |j| {
            vertices[base_idx + j] = button_vertices[j];
        }
    }

    sg.updateBuffer(self.vertex_buffer, sg.asRange(vertices[0..]));

    const bind = sg.Bindings{
        .vertex_buffers = ver: {
            var buffers = [_]sg.Buffer{.{}} ** 8;
            buffers[0] = self.vertex_buffer;
            break :ver buffers;
        },
        .index_buffer = self.index_buffer,
        .samplers = smp: {
            var samplers = [_]sg.Sampler{.{}} ** 16;
            samplers[0] = self.sampler;
            break :smp samplers;
        },
    };

    sg.applyPipeline(self.pip);
    sg.applyBindings(bind);
    sg.draw(0, 36, 1);
}

pub fn inputEventHandle(self: *Self, event: [*c]const Event) !void {
    if (self.getSymbolFromEvent(event)) |symbol| {
        const new_state: ?StateType = try self.pda.process(symbol);
        if (new_state) |state| {
            switch (state) {
                .Hidden => {},
                .FirstPage => {},
                .ControlMappings => {},
                .VideoSettings => {},
                .AudioSettings => {},
            }
        }
    }
}

// There are the following events of concerns we need to derive:
// - If an escape key is hit
// - If the mouse up event has occurred (only when the menu is being shown)
fn getSymbolFromEvent(self: Self, event: [*c]const Event) ?SymbolType {
    if (event.*.type == .KEY_UP) {
        switch (event.*.key_code) {
            .ESCAPE => return .Esc,
            else => {},
        }
    }

    if (self.pda.peakCurrentState() != .Hidden and event.*.type == .MOUSE_UP) {}

    return null;
}

pub fn deinit(self: *Self) void {
    self.pda.deinit();
    sg.destroyBuffer(self.vertex_buffer);
    sg.destroyBuffer(self.index_buffer);
    sg.destroyPipeline(self.pip);
    sg.destroySampler(self.sampler);
}

fn pdaTransitionFn(
    current_state: StateType,
    incoming: SymbolType,
    top_of_stack: ?SymbolType,
) ?PushdownAutomaton.Transition {
    const symbol_to_push: ?SymbolType = push: {
        switch (current_state) {
            .ControlMappings => break :push .ControlMappingsClick,
            .VideoSettings => break :push .VideoSettingsClick,
            .AudioSettings => break :push .AudioSettingsClick,
            else => break :push null,
        }
    };

    switch (incoming) {
        .Esc => {
            if (current_state == .Hidden) {
                return .{
                    .new_state = .FirstPage,
                    .push_symbol = symbol_to_push,
                };
            } else if (top_of_stack) |top| {
                return .{
                    .new_state = state: {
                        switch (top) {
                            .AudioSettingsClick => break :state .AudioSettings,
                            .VideoSettingsClick => break :state .VideoSettings,
                            .ControlMappingsClick => break :state .ControlMappings,
                            else => break :state .Hidden,
                        }
                    },
                    .pop_count = 1,
                };
            } else {
                return .{
                    .new_state = .Hidden,
                };
            }
        },
        .AudioSettingsClick => return .{
            .new_state = .AudioSettings,
            .push_symbol = symbol_to_push,
        },
        .VideoSettingsClick => return .{
            .new_state = .VideoSettings,
            .push_symbol = symbol_to_push,
        },
        .ControlMappingsClick => return .{
            .new_state = .ControlMappings,
            .push_symbol = symbol_to_push,
        },
    }

    return null;
}
