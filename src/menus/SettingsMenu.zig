//! Core type for settings menu
//! This is the first page of the menu and it should show the following
//! - Control mapping
//! - Video settings
//! - Audio settings
const std = @import("std");
const Allocator = std.mem.Allocator;

const Pda = @import("pda");
const Widget = @import("widget.zig").Widget;
const Event = @import("sokol").app.Event;
const Self = @This();

const SymbolType = enum {};
const StateType = enum {
    Hidden,
    FirstPage,
    ControlMappings,
    VideoSettings,
    AudioSettings,
};
const PushdownAutomaton = Pda(SymbolType, StateType);

pda: PushdownAutomaton = undefined,
top_left_coord: [2]f32 = undefined,
height: i32 = undefined,
width: i32 = undefined,
alloc: Allocator = undefined,

pub fn init(self: *Self, alloc: Allocator, top_left_coord: [2]f32, height: i32, width: i32) !void {
    self.alloc = alloc;
    self.top_left_coord = top_left_coord;
    self.height = height;
    self.width = width;
    self.pda = PushdownAutomaton{
        .current_state = .Hidden,
        .stack = std.ArrayList(SymbolType).init(alloc),
        .transitionFnPtr = pdaTransitionFn,
    };
}

pub fn render(self: *const Self) !void {
    if (self.pda.peakCurrentState == .Hidden) {
        return;
    }
}

pub fn inputEventHandle(self: *Self, event: [*c]const Event) !void {
    if (getSymbolFromEvent(event)) |symbol| {
        const new_state: StateType = self.pda.process(symbol);
        switch (new_state) {
            .Hidden => {},
            .FirstPage => {},
            .ControlMappings => {},
            .VideoSettings => {},
            .AudioSettings => {},
        }
    }
}

fn getSymbolFromEvent(event: [*]const Event) ?SymbolType {
    _ = event;
    return null;
}

pub fn deinit(self: *Self) void {
    self.pda.deinit();
}

fn pdaTransitionFn(
    current_state: StateType,
    incoming: SymbolType,
    top_of_stack: ?SymbolType,
) ?PushdownAutomaton.Transition {
    _ = current_state;
    _ = incoming;
    _ = top_of_stack;
}
