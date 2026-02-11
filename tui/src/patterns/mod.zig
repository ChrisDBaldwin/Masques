/// Pattern generator interface and registry.
/// Maps domain categories to their animation pattern generators.

const gradient = @import("../gradient.zig");
const portrait = @import("../portrait.zig");

pub const PatternContext = struct {
    width: usize,
    height: usize,
    tick: u32,
    seed: u32,
    intensity: f32,
    primary_color: [3]u8,
    dim_color: [3]u8,
    bright_color: [3]u8,
    domain_category: gradient.DomainCategory,
};

/// Pattern function signature: fills the cell buffer for one frame.
pub const PatternFn = *const fn (
    cells: *[portrait.max_h][portrait.max_w]portrait.PortraitCell,
    ctx: PatternContext,
) void;

const forge = @import("forge.zig");
const cybernetic = @import("cybernetic.zig");
const meta = @import("meta.zig");
const historical = @import("historical.zig");
const structural = @import("structural.zig");
const synthesis = @import("synthesis.zig");
const leverage = @import("leverage.zig");
const executive = @import("executive.zig");
const analytics = @import("analytics.zig");
const art = @import("art.zig");

/// Get the pattern generator for a domain category
pub fn getPattern(cat: gradient.DomainCategory) PatternFn {
    return switch (cat) {
        .forge => &forge.generate,
        .cybernetic => &cybernetic.generate,
        .meta => &meta.generate,
        .historical => &historical.generate,
        .structural => &structural.generate,
        .synthesis => &synthesis.generate,
        .leverage => &leverage.generate,
        .executive => &executive.generate,
        .analytics => &analytics.generate,
        .art => &art.generate,
    };
}
