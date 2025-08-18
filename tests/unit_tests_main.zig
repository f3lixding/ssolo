test {
    const std = @import("std");
    std.testing.refAllDecls(@This());

    inline for (.{
        @import("component_test.zig"),
    }) |source_file| std.testing.refAllDeclsRecursive(source_file);
}
