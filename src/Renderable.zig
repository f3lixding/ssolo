//! This is an interface for any object that is to be rendered.
//! The intention here is for each object type to be represented by an implementation of a Renderable.
//! And each implementation is to be the owner of the one or more instances of the object.
const std = @import("std");
const AllocPrintError = std.fmt.AllocPrintError;
const Event = @import("sokol").app.Event;

/// This error union represents all the possible error that could come from any of the rendering logic.
/// I am not sure if there is a better solution to this so I am going to stick with this for now.
/// This does mean all types that implement this interface need to reference this file.
pub const RenderableError = error{
    InitError,
    NullSkeletonData,
    RenderError,
} || AllocPrintError;

ptr: *anyopaque,
initFnPtr: *const fn (ptr: *anyopaque, alloc: std.mem.Allocator) RenderableError!void,
updateFnPtr: *const fn (ptr: *anyopaque, dt: f32) RenderableError!void,
renderFnPtr: *const fn (ptr: *const anyopaque) RenderableError!void,

inputEventHandleFnPtr: *const fn (ptr: *anyopaque, event: [*c]const Event) RenderableError!void,

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

        pub fn inputEventHandle(ptr: *anyopaque, event: [*c]const Event) RenderableError!void {
            const self: T = @ptrCast(@alignCast(ptr));
            // this has to be a pointer so there is no need for switch casing
            const actual_type = @typeInfo(T).pointer.child;
            if (@hasDecl(actual_type, "inputEventHandle")) {
                return self.inputEventHandle(event);
            }
        }
    };

    return .{
        .ptr = inner_ptr,
        .updateFnPtr = gen.update,
        .renderFnPtr = gen.render,
        .initFnPtr = gen.init,
        .inputEventHandleFnPtr = gen.inputEventHandle,
    };
}

pub fn initInner(self: *@This(), alloc: std.mem.Allocator) !void {
    return self.initFnPtr(self.ptr, alloc);
}

pub fn update(self: *@This(), dt: f32) !void {
    return self.updateFnPtr(self.ptr, dt);
}

pub fn render(self: *@This()) !void {
    return self.renderFnPtr(self.ptr);
}

pub fn inputEventHandle(self: *@This(), event: [*c]const Event) !void {
    return self.inputEventHandleFnPtr(self.ptr, event);
}
