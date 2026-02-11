/// Forge pattern: Rising sparks from a glowing core.
/// Used by: Crucible, Codesmith, Firekeeper.
/// A hot core at the bottom emits particles upward with heat shimmer.

const math = @import("../math.zig");
const gradient = @import("../gradient.zig");
const portrait = @import("../portrait.zig");
const color = @import("../color.zig");
const mod = @import("mod.zig");

pub fn generate(
    cells: *[portrait.max_h][portrait.max_w]portrait.PortraitCell,
    ctx: mod.PatternContext,
) void {
    var rng = math.Xorshift32.init(ctx.seed +% ctx.tick);
    const w = ctx.width;
    const h = ctx.height;
    const cx: f32 = @as(f32, @floatFromInt(w)) / 2.0;
    const base_y = h - 1;

    for (0..h) |y| {
        for (0..w) |x| {
            const fx: f32 = @floatFromInt(x);
            const fy: f32 = @floatFromInt(y);

            // Distance from center-bottom (the forge core)
            const dx = fx - cx;
            const dy = fy - @as(f32, @floatFromInt(base_y));
            const dist = @sqrt(dx * dx + dy * dy * 4.0); // stretch vertically

            // Core glow: bright at bottom-center, fading outward
            const max_dist: f32 = @as(f32, @floatFromInt(@max(w, h)));
            const core_intensity = @max(0.0, 1.0 - dist / (max_dist * 0.6));

            // Heat shimmer: offset by time
            const shimmer_phase: u8 = @truncate(ctx.tick *% 3 +% @as(u32, @intCast(x *% 17 +% y *% 31)));
            const shimmer = math.sinFull(shimmer_phase) * 0.1;

            var density = core_intensity * ctx.intensity + shimmer;

            // Rising heat columns
            const col_phase: u8 = @truncate(ctx.tick *% 2 +% @as(u32, @intCast(x *% 43)));
            const col_val = math.sinF(col_phase);
            const height_factor = @as(f32, @floatFromInt(base_y -| y)) / @as(f32, @floatFromInt(h));
            density += col_val * height_factor * 0.3 * ctx.intensity;

            // Sparks: random bright points that rise
            if (rng.bounded(100) < 3 and fy < @as(f32, @floatFromInt(base_y)) - 1.0) {
                density = @min(density + 0.5, 1.0);
            }

            density = @max(0.0, @min(density, 1.0));

            const char = gradient.densityChar(density);
            const fg = if (density > 0.7)
                ctx.bright_color
            else if (density > 0.3)
                ctx.primary_color
            else
                ctx.dim_color;

            cells[y][x] = .{
                .char = char,
                .fg = fg,
                .bold = density > 0.6,
            };
        }
    }
}
