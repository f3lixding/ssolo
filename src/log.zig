const std = @import("std");

const std_options: std.Options = .{
    .logFn = logFn,
};

pub fn logFn(
    comptime level: std.log.Level,
    comptime scope: @Type(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const scope_prefix = "(" ++ switch (scope) {
        .ssolo => @tagName(scope),
        else => if (@intFromEnum(level) <= @intFromEnum(std.log.Level.err))
            @tagName(scope)
        else
            return,
    } ++ "): ";

    const prefix = "[" ++ comptime level.asText() ++ "]" ++ scope_prefix;

    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();

    const stderr_file = std.fs.File.stderr();
    const buf: [1024]u8 = undefined;
    const stderr_writer = stderr_file.writer(&buf).interface;

    stderr_writer.print(prefix ++ format ++ "\n", args) catch return;
}
