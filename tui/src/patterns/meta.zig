/// Meta pattern: Bilateral mirror — left generates, right mirrors.
/// Used by: Mirror, Witness.
/// With periodic symmetry-breaking glitch.

const math = @import("../math.zig");
const gradient = @import("../gradient.zig");
const portrait = @import("../portrait.zig");
const color = @import("../color.zig");
const mod = @import("mod.zig");

pub fn generate(
    cells: *[portrait.max_h][portrait.max_w]portrait.PortraitCell,
    ctx: mod.PatternContext,
) void {
    var rng = math.Xorshift32.init(ctx.seed +% ctx.tick / 3); // slower variation
    const w = ctx.width;
    const h = ctx.height;
    const mid_x = w / 2;

    // Glitch: every ~90 ticks, break symmetry for 8 ticks
    const glitch_cycle = ctx.tick % 90;
    const is_glitching = glitch_cycle >= 82;

    // Generate left half
    for (0..h) |y| {
        for (0..mid_x) |x| {
            const fx: f32 = @floatFromInt(x);
            const fy: f32 = @floatFromInt(y);

            // Noise-like pattern from hash
            const cell_hash = math.hash(&[_]u8{
                @truncate(x),
                @truncate(y),
                @truncate(ctx.tick / 4),
            });
            const noise = @as(f32, @floatFromInt(cell_hash & 0xFF)) / 255.0;

            // Vertical wave
            const wave_phase: u8 = @truncate(ctx.tick *% 2 +% @as(u32, @intCast(y * 20)));
            const wave = math.sinF(wave_phase);

            // Horizontal gradient from center
            const center_dist = @as(f32, @floatFromInt(mid_x -| x)) / @as(f32, @floatFromInt(mid_x));

            var density = (noise * 0.5 + wave * 0.3 + center_dist * 0.2) * ctx.intensity;
            _ = fx;
            _ = fy;

            // Sparkle on the center divider line
            if (x == mid_x - 1) {
                density = @min(density + 0.3, 1.0);
            }

            density = @max(0.0, @min(density, 1.0));

            const glyphs = "|:.~*";
            const glyph_idx: usize = @intFromFloat(density * @as(f32, @floatFromInt(glyphs.len - 1)));
            const char = glyphs[@min(glyph_idx, glyphs.len - 1)];

            const fg = if (density > 0.6)
                ctx.primary_color
            else
                ctx.dim_color;

            cells[y][x] = .{
                .char = char,
                .fg = fg,
                .bold = density > 0.7,
            };

            // Mirror to right half
            const mirror_x = w - 1 - x;
            if (mirror_x < w) {
                if (is_glitching) {
                    // Glitch: right side gets scrambled
                    const glitch_char = gradient.density[rng.bounded(@intCast(gradient.density.len))];
                    cells[y][mirror_x] = .{
                        .char = glitch_char,
                        .fg = ctx.bright_color,
                        .bold = rng.bounded(3) == 0,
                    };
                } else {
                    // Perfect mirror (flip bracket-type chars)
                    const mirrored_char: u8 = switch (char) {
                        '(' => ')',
                        ')' => '(',
                        '[' => ']',
                        ']' => '[',
                        '{' => '}',
                        '}' => '{',
                        '<' => '>',
                        '>' => '<',
                        '/' => '\\',
                        '\\' => '/',
                        else => char,
                    };
                    cells[y][mirror_x] = .{
                        .char = mirrored_char,
                        .fg = fg,
                        .bold = density > 0.7,
                    };
                }
            }
        }
    }

    // Center divider line
    for (0..h) |y| {
        if (mid_x < w) {
            const div_phase: u8 = @truncate(ctx.tick *% 5 +% @as(u32, @intCast(y * 30)));
            const div_brightness = math.sinF(div_phase);
            cells[y][mid_x] = .{
                .char = '|',
                .fg = if (div_brightness > 0.5) ctx.bright_color else ctx.primary_color,
                .bold = true,
            };
        }
    }
}
