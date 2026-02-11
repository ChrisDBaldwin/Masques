/// Executive pattern: Ticker bars — vertical bars grow/shrink
/// like a live market display with a scrolling ticker overlay.
/// Used by: Chairman, Chief, Closer, Comptroller, Counsel, etc.

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

    // Bar chart: each column is a bar with varying height
    for (0..w) |x| {
        // Bar height oscillates with a per-column seed
        const bar_seed = rng.next();
        const base_height: f32 = @as(f32, @floatFromInt(bar_seed % @as(u32, @intCast(h)))) / @as(f32, @floatFromInt(h));
        const phase: u8 = @truncate(ctx.tick *% 2 +% @as(u32, @intCast(x *% 17)) +% bar_seed);
        const wave = math.sinFull(phase);
        const bar_h_f = (base_height * 0.6 + wave * 0.3 + 0.1) * ctx.intensity * @as(f32, @floatFromInt(h));
        const bar_h: usize = @intFromFloat(@max(1.0, @min(bar_h_f, @as(f32, @floatFromInt(h)))));

        // Determine bar color: green if growing, red if shrinking
        const prev_phase: u8 = @truncate(ctx.tick *% 2 -% 2 +% @as(u32, @intCast(x *% 17)) +% bar_seed);
        const prev_wave = math.sinFull(prev_phase);
        const is_growing = wave > prev_wave;

        const bar_color = if (is_growing) ctx.primary_color else ctx.dim_color;

        for (0..bar_h) |dy| {
            const y = h - 1 - dy;
            if (y < h) {
                const filled = dy < bar_h;
                _ = filled;
                const char: u8 = if (dy == bar_h - 1) '=' else '#';
                cells[y][x] = .{
                    .char = char,
                    .fg = if (dy == bar_h - 1) ctx.bright_color else bar_color,
                    .bold = dy == bar_h - 1,
                };
            }
        }
    }

    // Scrolling ticker overlay on top row
    const ticker = ">>> MSQE +2.4%  DRAFT +5.1%  ROLE -0.3%  TEAM +1.7% <<<  ";
    const ticker_offset: usize = @intCast((ctx.tick / 2) % @as(u32, @intCast(ticker.len)));
    for (0..w) |x| {
        const ti = (x + ticker_offset) % ticker.len;
        cells[0][x] = .{
            .char = ticker[ti],
            .fg = ctx.bright_color,
            .bold = true,
        };
    }
}
