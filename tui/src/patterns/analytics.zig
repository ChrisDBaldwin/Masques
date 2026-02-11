/// Analytics pattern: Scatter plot with trend line.
/// Points appear and fade, trend line undulates.
/// Used by: Chartwright.

const math = @import("../math.zig");
const portrait = @import("../portrait.zig");
const mod = @import("mod.zig");

pub fn generate(
    cells: *[portrait.max_h][portrait.max_w]portrait.PortraitCell,
    ctx: mod.PatternContext,
) void {
    var rng = math.Xorshift32.init(ctx.seed);
    const w = ctx.width;
    const h = ctx.height;

    // Clear
    for (0..h) |y| {
        for (0..w) |x| {
            cells[y][x] = .{ .char = ' ' };
        }
    }

    // Draw axes
    if (h > 2 and w > 2) {
        // Y axis
        for (0..h - 1) |y| {
            cells[y][1] = .{ .char = '|', .fg = ctx.dim_color };
        }
        // X axis
        for (1..w) |x| {
            cells[h - 2][x] = .{ .char = '-', .fg = ctx.dim_color };
        }
        // Origin
        cells[h - 2][1] = .{ .char = '+', .fg = ctx.dim_color };

        // Y-axis ticks
        for (0..h / 3) |i| {
            const y = h - 2 - (i + 1) * 2;
            if (y < h) {
                cells[y][0] = .{ .char = '-', .fg = ctx.dim_color };
            }
        }
    }

    // Scatter points: deterministic from seed, but some fade in/out over time
    const num_points: usize = @min(w * h / 6, 30);
    for (0..num_points) |_| {
        const px = rng.bounded(@intCast(w -| 3)) + 2;
        const py = rng.bounded(@intCast(h -| 3));
        const point_phase: u8 = @truncate(ctx.tick +% rng.next());
        const visibility = math.sinF(point_phase);

        if (visibility > 0.3 / ctx.intensity) {
            const char: u8 = if (visibility > 0.7) 'O' else 'o';
            cells[py][px] = .{
                .char = char,
                .fg = if (visibility > 0.7) ctx.bright_color else ctx.primary_color,
                .bold = visibility > 0.8,
            };
        }
    }

    // Trend line: undulating curve
    if (w > 4 and h > 4) {
        for (2..w) |x| {
            const t: f32 = @as(f32, @floatFromInt(x - 2)) / @as(f32, @floatFromInt(w - 2));
            // Base trend: downward slope (from top-left to bottom-right in chart coords)
            const base_y = t * @as(f32, @floatFromInt(h - 4));
            // Undulation
            const wave_phase: u8 = @truncate(ctx.tick *% 3 +% @as(u32, @intCast(x * 20)));
            const wave = math.sinFull(wave_phase) * 1.5;
            const y_f = base_y + wave;
            const y_i: isize = @intFromFloat(y_f);
            if (y_i >= 0 and y_i < @as(isize, @intCast(h - 2))) {
                const uy: usize = @intCast(y_i);
                cells[uy][x] = .{
                    .char = '~',
                    .fg = ctx.primary_color,
                    .bold = true,
                };
            }
        }
    }
}
