//! This is an interface for any object that is to be rendered.
//! The intention here is for each object type to be represented by an implementation of a Renderable.
//! And each implementation is to be the owner of the one or more instances of the object.
const std = @import("std");
const AllocPrintError = std.fmt.AllocPrintError;

/// This error union represents all the possible error that could come from any of the rendering logic.
/// I am not sure if there is a better solution to this so I am going to stick with this for now.
/// This does mean all types that implement this interface need to reference this file.
pub const RenderableError = error{
    NullSkeletonData,
    RenderError,
} || AllocPrintError;

ptr: *anyopaque,
initFnPtr: *const fn (ptr: *anyopaque, alloc: std.mem.Allocator) RenderableError!void,
updateFnPtr: *const fn (ptr: *anyopaque, dt: f32) RenderableError!void,
renderFnPtr: *const fn (ptr: *const anyopaque) RenderableError!void,

pub fn init(inner_ptr: anytype) !@This() {
    const T: type = @TypeOf(inner_ptr);

    const gen = struct {
        pub fn init(ptr: *anyopaque, alloc: std.mem.Allocator) RenderableError!void {
            const self: T = @ptrCast(@alignCast(ptr));
            return self.init(alloc);
        }

        pub fn update(ptr: *anyopaque, dt: f32) RenderableError!void {
            const self: T = @ptrCast(@alignCast(ptr));
            return self.update(dt);
        }

        pub fn render(ptr: *const anyopaque) RenderableError!void {
            const self: T = @constCast(@ptrCast(@alignCast(ptr)));
            return self.render();
        }
    };

    return .{
        .ptr = inner_ptr,
        .updateFnPtr = gen.update,
        .renderFnPtr = gen.render,
        .initFnPtr = gen.init,
    };
}

pub fn init_inner(self: *@This(), alloc: std.mem.Allocator) !void {
    return self.initFnPtr(self.ptr, alloc);
}

pub fn update(self: *@This(), dt: f32) !void {
    return self.updateFnPtr(self.ptr, dt);
}

pub fn render(self: *@This()) !void {
    return self.renderFnPtr(self.ptr);
}

test "test implement" {
    const Renderable = @import("Renderable.zig");
    const Car = struct {
        brand: []const u8,
        doors: u32,

        pub fn init(self: *@This(), name: []const u8) !void {
            _ = self;
            _ = name;
            std.debug.print("Init called\n", .{});
        }

        pub fn update(self: *@This(), dt: f32) !void {
            _ = dt;
            std.debug.print("Car brand is: {s}\n", .{self.brand});
        }

        pub fn render(self: *const @This()) !void {
            std.debug.print("Number of doors is: {any}\n", .{self.doors});
        }
    };

    var ford_focus = Car{
        .brand = "Ford",
        .doors = 5,
    };

    var renderable = Renderable.init(&ford_focus) catch unreachable;
    renderable.update(1.0) catch unreachable;
    renderable.render() catch unreachable;
}

fn call_announce(incoming: anytype, to_log: []const u8) void {
    incoming.log(to_log);
}
const Incoming = struct {
    pub fn log(self: Incoming, to_log: []const u8) void {
        _ = self;
        std.debug.print("{s}\n", .{to_log});
    }
};
test "test anytype" {
    const incoming = Incoming{};
    call_announce(incoming, "hello world");
}
