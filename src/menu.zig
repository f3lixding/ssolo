//! In all honesty this is probably over engineered. The design tenet here is that [Widget] should be reusubale, and composable.
//! I am also using this as an opportunity to learn about comptime
const std = @import("std");
const Allocator = std.mem.Allocator;
const Renderable = @import("Renderable.zig");
const RenderableError = Renderable.RenderableError;
const Event = @import("sokol").app.Event;
const Pda = @import("pda");

pub const NoopWidget = void;

/// A [Widget] is a way to represent a blob of content to display.
/// It implements [Renderable].
/// A [Widget] can contain other widgets. They are composed via comptime logic.
/// A [Widget] that has different number of children are seen as different types.
pub fn Widget(comptime config: struct {
    StateType: type,
    SymbolType: type,
    widgets: []const type = &.{},
}) type {
    return struct {
        const StateType = config.StateType;
        const SymbolType = config.SymbolType;
        const Self = @This();

        alloc: Allocator = undefined,
        pda: Pda(StateType, SymbolType) = undefined,
        widgets: WidgetTuple(config.widgets),

        pub fn get_one(self: Self) i32 {
            _ = self;
            return 1;
        }

        // -- impl Renderable start --
        pub fn init(self: *Self, alloc: Allocator) RenderableError!void {
            self.alloc = alloc;

            inline for (@typeInfo(@TypeOf(self.widgets)).@"struct".fields) |field| {
                if (@hasDecl(field.type, "init")) {
                    try @field(self.widgets, field.name).init(alloc);
                }
            }
        }

        // TODO: need to figure out how to render them based on the sizes they are configured
        // in the parent
        pub fn render(self: *const Self) RenderableError!void {
            inline for (@typeInfo(@TypeOf(self.widgets)).@"struct".fields) |field| {
                if (@hasDecl(field.type, "render")) {
                    try @field(self.widgets, field.name).render();
                }
            }
        }

        pub fn inputEventHandle(self: *Self, event: [*c]const Event) RenderableError!void {
            inline for (@typeInfo(@TypeOf(self.widgets)).@"struct".fields) |field| {
                if (@hasDecl(field.type, "inputEventHandle")) {
                    try @field(self.widgets, field.name).inputEventHandle(event);
                }
            }
        }

        pub fn deinit(self: *Self) void {
            inline for (@typeInfo(@TypeOf(self.widgets)).@"struct".fields) |field| {
                if (@hasDecl(field.type, "deinit")) {
                    @field(self.widgets, field.name).deinit();
                }
            }

            self.pda.deinit();
        }
        // -- impl Renderable end --
    };
}

fn WidgetTuple(comptime widget_types: []const type) type {
    var fields: [widget_types.len]std.builtin.Type.StructField = undefined;

    for (widget_types, 0..) |WidgetType, i| {
        const field_name = std.fmt.comptimePrint("widget_field_{d}", .{i});
        fields[i] = std.builtin.Type.StructField{ .name = field_name, .type = WidgetType, .default_value_ptr = null, .is_comptime = false, .alignment = @alignOf(WidgetType) };
    }

    return @Type(std.builtin.Type{ .@"struct" = std.builtin.Type.Struct{
        .layout = .auto,
        .fields = &fields,
        .decls = &.{},
        .is_tuple = false,
    } });
}

test "init" {
    const SubWidget = Widget(.{
        .StateType = i32,
        .SymbolType = i32,
        .widgets = &.{},
    });
    const MainWidget = Widget(.{
        .StateType = i32,
        .SymbolType = i32,
        .widgets = &.{SubWidget},
    });
    std.debug.print("MainWidget: {any}\n", .{MainWidget});

    const sub_widget = SubWidget{ .widgets = .{} };
    const main_widget = MainWidget{ .widgets = .{ .widget_field_0 = sub_widget } };
    // std.debug.print("main_widget: {any}\n", .{main_widget});
    std.debug.print("main_widget_return_one: {d}\n", .{main_widget.get_one()});
}
