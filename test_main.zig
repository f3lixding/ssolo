test {
    const std = @import("std");
    std.testing.refAllDecls(@This());

    inline for (.{
        @import("tests/component_test.zig"),
        @import("tests/entity_test.zig"),
    }) |source_file| std.testing.refAllDeclsRecursive(source_file);
}
