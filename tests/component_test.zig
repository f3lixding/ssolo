const zigimg = @import("zigimg");
const std = @import("std");

test "component test" {
    const bgr = zigimg.PixelFormat.bgr24;
    std.debug.print("component test ran\n", .{});
    std.debug.print("bgr: {any}\n", .{bgr});
}

test "regex test" {
    const bgr = zigimg.PixelFormat.bgr24;
    std.debug.print("regex test ran\n", .{});
    std.debug.print("bgr: {any}\n", .{bgr});
}
