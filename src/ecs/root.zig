//! An ECS to be used by the game to manage states.
//! I am using it because I feel like learning it and I don't yet fully understand the trade offs between ECS and fat structs passing.
//!
//! I am opting to use archetypes because I think fast look up would be more valuable in more cases than fast creation (though in that regard
//! I am equally unsure about the tradeoffs).
//!
//! There are the following main components to the ECS implementations (and they are not too different from a typical implementation):
//!
//! ## System
//! This is the equivalent of a game world, where everything about the environment is accessible.
//! It is also where the behavior of [Component]s live.
//! Its responsibilities are the following:
//! - Entity creation
//! - Entity removal
//! - Entity updates (this also includes collision detection)
//! - Entity rendering
//!
//! ## Component
//! A component is a collection of data dedicated to an attribute. These are almost always data that uniquely perstains to an instance of
//! an object (i.e. Entity). Attributes or resources that are meant to be shared amongst all components are stored on [System] and retrieved
//! when it's needed.
//! It is also the basis with which queries are made (and often with a combination of Components, see [Archetype]).
//!
//! ## Archetype
//! A combination of components. Each Archetype is to have its own signature, with which they are queried quickly.
//! Within each Archetype,
//! The sequence of data retrieval is as follows:
//! System (World) -> Archetype Map (K: signature, V: Archetype) -> Component Map (K: signature, V: Components) -> Components
//!
//! ## Entity
//! This is the id that is used to represent an instance of an object. As per ECS operating philosophy, therer are no behavior, no data directly
//! attached to the Entity. It merely serves as a key with which queries are to be made for info about the Entity.
//! Entities are to be stored in their respective Achetypes.
//!
//! ## Entity Location
//! Because Entities are not directly stored in System, the whereabouts of an Entity need to be declared. If an event for removal is called
//! for an Entity with a given id, the sequence of retrieval is as follows:
//! Id -> Entity Location -> Associated Archetype + index
//! Because we will likely be moving some elements around during a removal, we would also need to be updating the Entity Location of the Entity
//! that was moved, if any.

pub const System = @import("system.zig").System;
pub const Archetype = @import("entity.zig").Archetype;
pub const ArchetypeSignature = @import("entity.zig").ArchetypeSignature;
pub const Entity = @import("entity.zig").Entity;
pub const EntityBundle = @import("entity.zig").EntityBundle;
pub const ComponentId = @import("components.zig").ComponentId;
pub const AllComponentCombinations = @import("components.zig").AllComponentCombinations;

const sg = @import("sokol").gfx;
const InitBundle = @import("../util.zig").InitBundle;

pub const RenderContext = struct {
    init_bundle: InitBundle = undefined,
    init: *const fn (*RenderContext) anyerror!void,
    get_pip_fn_ptr: *const fn () sg.Pipeline,
    get_sampler_fn_ptr: *const fn () sg.Sampler,
    get_view_fn_ptr: *const fn () sg.View,
};
