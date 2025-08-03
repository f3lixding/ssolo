//! Generic pushdown automaton
//! This is main meant to be used to manage menu state (since game play state would have too many parallel states for a PDA)
//! Consumer needs to provide the following in order to produce a functioning PDA:
//! - Symbol type
//! - State type
//! - Callback for transition handling. This is a callback that accepts current_state, incoming, top of stack and
//!   in turn produces a [Transition]. The [Transition] is leveraged by the PDA to programmatically maintain its state via a declarative protocol.
const std = @import("std");
const ArrayList = std.ArrayList;

pub fn Pda(comptime StateType: type, comptime SymbolType: type) type {
    return struct {
        const Self = @This();
        const TransitionFnPtr = *const fn (current_state: StateType, incoming: SymbolType, top_of_stack: ?SymbolType) ?Transition;

        pub const Transition = struct {
            new_state: StateType,
            push_symbol: ?SymbolType = null,
            pop_count: u32 = 0,
        };

        current_state: StateType,
        stack: ArrayList(SymbolType),
        transitionFnPtr: TransitionFnPtr,

        pub fn init(alloc: std.mem.Allocator, init_state: StateType, transition_fn: TransitionFnPtr) Self {
            return .{
                .current_state = init_state,
                .stack = ArrayList(SymbolType).init(alloc),
                .transitionFnPtr = transition_fn,
            };
        }

        pub fn deinit(self: Self) void {
            self.stack.deinit();
        }

        /// Ingest the incoming symbol and returns an applicable new state
        /// A value of null signifies that no state transition was deemed necessary
        pub fn process(self: *Self, input_symbol: SymbolType) !?StateType {
            const top_stack: ?SymbolType = self.stack.getLastOrNull();

            if (self.transitionFnPtr(self.current_state, input_symbol, top_stack)) |transition| {
                const new_state: StateType = transition.new_state;
                const push_symbol: ?SymbolType = transition.push_symbol;
                const pop_count = transition.pop_count;

                self.current_state = new_state;
                for (0..pop_count) |_| {
                    _ = self.stack.pop();
                }

                if (push_symbol) |symbol| {
                    try self.stack.append(symbol);
                }

                return new_state;
            }

            return null;
        }
    };
}

test "overall test" {
    const testing_alloc = std.testing.allocator;
    const assert = std.debug.assert;

    const TestState = enum {
        Hidden,
        BaseMenu,
        ButtonConfig,
        Graphics,
        Sound,
    };

    const TestSymbol = enum {
        Esc,
        ButtonConfigRegister,
        GraphicsRegister,
        SoundRegister,
    };

    const trans_fn = struct {
        // Aliasing the type here for convenience
        pub const Transition = Pda(TestState, TestSymbol).Transition;
        pub fn transFn(current_state: TestState, incoming: TestSymbol, top_of_stack: ?TestSymbol) ?Transition {
            const symbol_to_push: ?TestSymbol = push: {
                switch (current_state) {
                    .ButtonConfig => break :push .ButtonConfigRegister,
                    .Graphics => break :push .GraphicsRegister,
                    .Sound => break :push .SoundRegister,
                    .BaseMenu => break :push .Esc,
                    else => break :push null,
                }
            };

            switch (incoming) {
                .Esc => {
                    if (current_state == .Hidden) {
                        return .{
                            .new_state = .BaseMenu,
                        };
                    } else if (top_of_stack) |top| {
                        return .{
                            .new_state = state: {
                                switch (top) {
                                    .SoundRegister => break :state .Sound,
                                    .GraphicsRegister => break :state .Graphics,
                                    .ButtonConfigRegister => break :state .ButtonConfig,
                                    .Esc => break :state .BaseMenu,
                                }
                            },
                            .pop_count = 1,
                        };
                    } else {
                        // here we are not in .Hidden and we don't have anything in the stack
                        return .{
                            .new_state = .Hidden,
                        };
                    }
                },
                .SoundRegister => {
                    return .{
                        .new_state = .Sound,
                        .push_symbol = symbol_to_push,
                    };
                },
                .GraphicsRegister => {
                    return .{
                        .new_state = .Graphics,
                        .push_symbol = symbol_to_push,
                    };
                },
                .ButtonConfigRegister => {
                    return .{
                        .new_state = .ButtonConfig,
                        .push_symbol = symbol_to_push,
                    };
                },
            }
        }
    }.transFn;

    var pda = Pda(TestState, TestSymbol).init(
        testing_alloc,
        .Hidden,
        trans_fn,
    );
    defer pda.deinit();

    var process_result: ?TestState = undefined;

    process_result = try pda.process(.Esc);
    assert(process_result == TestState.BaseMenu);

    process_result = try pda.process(.ButtonConfigRegister);
    assert(process_result == TestState.ButtonConfig);

    process_result = try pda.process(.GraphicsRegister);
    assert(process_result == TestState.Graphics);

    process_result = try pda.process(.Esc);
    assert(process_result == TestState.ButtonConfig);

    process_result = try pda.process(.Esc);
    assert(process_result == TestState.BaseMenu);

    process_result = try pda.process(.Esc);
    assert(process_result == TestState.Hidden);
    assert(pda.stack.items.len == 0);
}
