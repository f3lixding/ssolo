//! In all honesty this is probably over engineered. The design tenet here is that [Widget] should be reusubale, and composable.
//! I am also using this as an opportunity to learn about comptime
const std = @import("std");
const Allocator = std.mem.Allocator;
const Event = @import("sokol").app.Event;
const assert = std.debug.assert;

pub const WidgetConfig = struct {
    /// The parent type where the logic concerning to this widget is held
    /// The core type is stateful and is responsible of keeping states of interest
    CoreType: type,
    /// The children widgets this widget owns
    widgets: []const type = &.{},
};

/// A [Widget] is a way to represent a blob of content to display.
/// It implements [Renderable].
/// A [Widget] can contain other widgets. They are composed via comptime logic.
/// A [Widget] that has different number of children are seen as different types.
pub fn Widget(comptime config: WidgetConfig) type {
    return struct {
        const CoreType = config.CoreType;
        const Self = @This();

        alloc: Allocator = undefined,
        core: CoreType,
        widgets: ?WidgetTuple(config.widgets) = null,
        top_left_coord: [2]f32 = .{ 0.0, 0.0 },
        height: i32 = 10,
        width: i32 = 10,

        // -- impl Renderable start --
        pub fn init(self: *Self, alloc: Allocator) !void {
            self.alloc = alloc;

            inline for (@typeInfo(WidgetTuple(config.widgets)).@"struct".fields) |field| {
                const field_fields = @typeInfo(field.type).@"struct".fields;
                const widget_field = inline for (field_fields) |field_field| {
                    if (comptime std.mem.eql(u8, field_field.name, "widget")) {
                        break field_field;
                    }
                } else {
                    @compileLog(field.name);
                    @compileError("widget config field struct does not contain required field widget");
                };

                if (@hasDecl(widget_field.type, "init")) {
                    if (self.widgets) |widgets| {
                        const cur_widget_wrapper = @field(widgets, field.name);
                        var cur_widget = @field(cur_widget_wrapper, widget_field.name);
                        try cur_widget.init(alloc);
                    }
                }
            }

            if (@hasDecl(CoreType, "init")) {
                try self.core.init(alloc, self.top_left_coord, self.height, self.width);
            }
        }

        pub fn render(self: *const Self) !void {
            inline for (@typeInfo(WidgetTuple(config.widgets)).@"struct".fields) |field| {
                const field_fields = @typeInfo(field.type).@"struct".fields;
                const widget_field = inline for (field_fields) |field_field| {
                    if (comptime std.mem.eql(u8, field_field.name, "widget")) {
                        break field_field;
                    }
                } else {
                    @compileError("widget config field struct does not contain required field widget");
                };

                if (@hasDecl(widget_field.type, "render")) {
                    if (self.widgets) |widgets| {
                        const cur_widget_wrapper = @field(widgets, field.name);
                        const cur_widget = @field(cur_widget_wrapper, widget_field.name);
                        try cur_widget.render();
                    }
                }
            }

            if (@hasDecl(CoreType, "render")) {
                try self.core.render();
            }
        }

        pub fn inputEventHandle(self: *Self, event: [*c]const Event) !void {
            inline for (@typeInfo(WidgetTuple(config.widgets)).@"struct".fields) |field| {
                const field_fields = @typeInfo(field.type).@"struct".fields;
                const widget_field = inline for (field_fields) |field_field| {
                    if (comptime std.mem.eql(u8, field_field.name, "widget")) {
                        break field_field;
                    }
                } else {
                    @compileError("widget config field struct does not contain required field widget");
                };

                if (@hasDecl(widget_field.type, "inputEventHandle")) {
                    const cur_widget_wrapper = @field(self.widgets, field.name);
                    const cur_widget = @field(cur_widget_wrapper, widget_field.name);
                    try cur_widget.inputEventHandle(event);
                }
            }

            if (@hasDecl(CoreType, "inputEventHandle")) {
                try self.core.inputEventHandle(event);
            }
        }

        pub fn deinit(self: *Self) void {
            inline for (@typeInfo(WidgetTuple(config.widgets)).@"struct".fields) |field| {
                const field_fields = @typeInfo(field.type).@"struct".fields;
                const widget_field = inline for (field_fields) |field_field| {
                    if (comptime std.mem.eql(u8, field_field.name, "widget")) {
                        break field_field;
                    }
                } else {
                    @compileError("widget config field struct does not contain required field widget");
                };

                if (@hasDecl(widget_field.type, "deinit")) {
                    const cur_widget_wrapper = @field(self.widgets, field.name);
                    const cur_widget = @field(cur_widget_wrapper, widget_field.name);
                    try cur_widget.deinit();
                }
            }

            if (@hasDecl(CoreType, "deinit")) {
                self.core.deinit();
            }
        }
        // -- impl Renderable end --
    };
}

fn WidgetWrapper(comptime widget_type: type) type {
    return struct { widget: widget_type };
}

fn WidgetTuple(comptime widget_types: []const type) type {
    var fields: [widget_types.len]std.builtin.Type.StructField = undefined;

    for (widget_types, 0..) |WidgetType, i| {
        const field_name = std.fmt.comptimePrint("widget_field_{d}", .{i});
        fields[i] = std.builtin.Type.StructField{
            .name = field_name,
            .type = WidgetWrapper(WidgetType),
            .default_value_ptr = null,
            .is_comptime = false,
            .alignment = @alignOf(WidgetType),
        };
    }

    return @Type(std.builtin.Type{ .@"struct" = std.builtin.Type.Struct{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

test "init" {
    // typedef
    const MainCore = struct {
        pub fn init(
            self: *@This(),
            alloc: std.mem.Allocator,
            top_left_coord: [2]f32,
            height: i32,
            width: i32,
        ) !void {
            _ = self;
            _ = alloc;
            _ = top_left_coord;
            _ = height;
            _ = width;
            std.debug.print("main widget init called\n", .{});
        }

        pub fn render(self: *const @This()) !void {
            _ = self;
            std.debug.print("main core render called\n", .{});
        }
    };
    const MainWidget = Widget(.{
        .CoreType = MainCore,
    });

    const main_core = MainCore{};
    var main_widget = MainWidget{
        .core = main_core,
    };
    main_widget.init(std.testing.allocator) catch unreachable;

    // trying out with main core directly as a subtype (as opposed to wrapped in a widget)
    const BigCore = struct {
        pub fn init(
            self: *@This(),
            alloc: std.mem.Allocator,
            top_left_coord: [2]f32,
            height: i32,
            width: i32,
        ) !void {
            _ = self;
            _ = alloc;
            _ = top_left_coord;
            _ = height;
            _ = width;
            std.debug.print("big widget init called\n", .{});
        }

        pub fn render(self: *const @This()) !void {
            _ = self;
            std.debug.print("big core render called\n", .{});
        }
    };

    const BigWidget = Widget(.{
        .CoreType = BigCore,
        .widgets = &.{
            MainWidget,
        },
    });

    var big_widget = BigWidget{
        .core = BigCore{},
        .widgets = .{
            .widget_field_0 = .{ .widget = main_widget },
        },
        .top_left_coord = .{ 1.0, 1.0 },
        .height = 10,
        .width = 10,
    };
    big_widget.init(std.testing.allocator) catch unreachable;
    big_widget.render() catch unreachable;
}
