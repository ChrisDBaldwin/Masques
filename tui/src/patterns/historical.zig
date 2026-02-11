/// Historical pattern: Text erosion — layered text fragments that fade
/// and overwrite, old showing through new. Used by: Palimpsest.

const math = @import("../math.zig");
const portrait = @import("../portrait.zig");
const mod = @import("mod.zig");

const fragments = [_][]const u8{
    "thus it was",
    "in the year",
    "they foresaw",
    "as before so",
    "the pattern",
    "repeats here",
    "once written",
    "never truly",
};

pub fn generate(
    cells: *[portrait.max_h][portrait.max_w]portrait.PortraitCell,
    ctx: mod.PatternContext,
) void {
    var rng = math.Xorshift32.init(ctx.seed);
    const w = ctx.width;
    const h = ctx.height;

    // Base: faded old text layer
    for (0..h) |y| {
        const frag_idx = (y + ctx.seed / 7) % fragments.len;
        const frag = fragments[frag_idx];
        const offset: usize = @intCast((ctx.tick / 8 + @as(u32, @intCast(y * 3))) % @as(u32, @intCast(@max(frag.len, 1))));
        for (0..w) |x| {
            const src_idx = (x + offset) % frag.len;
            // Erosion: some chars fade based on time
            const erosion_phase: u8 = @truncate(ctx.tick +% @as(u32, @intCast(x * 7 +% y * 13)));
            const erosion = math.sinF(erosion_phase);
            if (erosion > 0.6 / ctx.intensity) {
                cells[y][x] = .{
                    .char = frag[src_idx],
                    .fg = ctx.dim_color,
                };
            } else {
                cells[y][x] = .{ .char = '.' , .fg = ctx.dim_color };
            }
        }
    }

    // Overlay: brighter newer text that scrolls differently
    const overlay_y_offset: usize = @intCast((ctx.tick / 12) % @as(u32, @intCast(h)));
    for (0..@min(3, h)) |dy| {
        const y = (overlay_y_offset + dy) % h;
        const frag_idx = (rng.bounded(@intCast(fragments.len)));
        const frag = fragments[frag_idx];
        const x_start: usize = rng.bounded(@intCast(w / 2));
        for (x_start..@min(x_start + frag.len, w)) |x| {
            const fi = x - x_start;
            const fade = @as(f32, @floatFromInt(fi)) / @as(f32, @floatFromInt(frag.len));
            cells[y][x] = .{
                .char = frag[fi],
                .fg = if (fade < 0.5) ctx.bright_color else ctx.primary_color,
                .bold = fade < 0.3 and ctx.intensity > 0.7,
            };
        }
    }
}
