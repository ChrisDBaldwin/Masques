/// Art pattern: Flowing brushstrokes and color washes.
/// Used by: Glyph, Loom, Orchard, Kiln, Lathe, Gilder, Stencil, Easel.
/// Sweeping diagonal strokes with dappled texture, like paint on canvas.

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

    for (0..h) |y| {
        for (0..w) |x| {
            const fx: f32 = @floatFromInt(x);
            const fy: f32 = @floatFromInt(y);
            const fw: f32 = @floatFromInt(w);
            const fh: f32 = @floatFromInt(h);

            // Diagonal brushstroke waves — two crossing strokes
            const stroke1_phase: u8 = @truncate(ctx.tick *% 2 +% @as(u32, @intCast(x *% 11 +% y *% 23)));
            const stroke1 = math.sinFull(stroke1_phase);

            const stroke2_phase: u8 = @truncate(ctx.tick *% 3 +% @as(u32, @intCast(x *% 29 +% y *% 7)));
            const stroke2 = math.sinFull(stroke2_phase);

            // Cross-hatching: diagonal lines create texture
            const diag1 = @mod(fx + fy + @as(f32, @floatFromInt(ctx.tick)) * 0.3, 4.0);
            const diag2 = @mod(fx - fy + @as(f32, @floatFromInt(ctx.tick)) * 0.2 + fw, 5.0);
            const hatch = if (diag1 < 1.0 or diag2 < 1.0) @as(f32, 0.15) else @as(f32, 0.0);

            // Radial vignette from center — brighter in the middle
            const cx = fw / 2.0;
            const cy = fh / 2.0;
            const dx = (fx - cx) / cx;
            const dy = (fy - cy) / cy;
            const vignette = 1.0 - @sqrt(dx * dx + dy * dy) * 0.4;

            // Combine
            var density = (stroke1 * 0.3 + stroke2 * 0.2 + 0.4) * vignette * ctx.intensity + hatch;

            // Dapple: random spots of brightness like paint splatter
            if (rng.bounded(100) < 5) {
                density = @min(density + 0.3, 1.0);
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
                .bold = density > 0.65,
            };
        }
    }
}
