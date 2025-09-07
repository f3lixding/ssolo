const zigimg = @import("zigimg");
const std = @import("std");
const ecs = @import("../src/ecs/root.zig");
const AllComponentCombinations = ecs.AllComponentCombinations;

test "pregenerate component combination tuples" {
    const combo = AllComponentCombinations[10];
    inline for (combo) |component| {
        @compileLog(@typeName(component));
    }
}
