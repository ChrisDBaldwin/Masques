/// Synthesis pattern: Braiding threads — sine waves at different frequencies
/// weaving over/under each other. Used by: Weaver.

const math = @import("../math.zig");
const portrait = @import("../portrait.zig");
const mod = @import("mod.zig");

pub fn generate(
    cells: *[portrait.max_h][portrait.max_w]portrait.PortraitCell,
    ctx: mod.PatternContext,
) void {
    const w = ctx.width;
    const h = ctx.height;
    const mid_y: f32 = @as(f32, @floatFromInt(h)) / 2.0;

    // Clear
    for (0..h) |y| {
        for (0..w) |x| {
            cells[y][x] = .{ .char = ' ' };
        }
    }

    // Draw 3 braiding threads at different frequencies
    const thread_colors = [3][3]u8{ ctx.primary_color, ctx.bright_color, ctx.dim_color };
    const thread_chars = [3]u8{ '~', '^', 'v' };
    const freqs = [3]u8{ 8, 12, 6 }; // phase multiplier per column
    const offsets = [3]u8{ 0, 85, 170 }; // phase offsets (roughly thirds of 256)

    for (0..3) |thread_idx| {
        for (0..w) |x| {
            const phase: u8 = @truncate(
                @as(u32, @intCast(x)) *% @as(u32, freqs[thread_idx]) +%
                    ctx.tick *% 3 +%
                    @as(u32, offsets[thread_idx]),
            );
            const wave = math.sinFull(phase);
            const amplitude: f32 = @as(f32, @floatFromInt(h)) * 0.35 * ctx.intensity;
            const y_f = mid_y + wave * amplitude;
            const y_i: isize = @intFromFloat(y_f);

            if (y_i >= 0 and y_i < @as(isize, @intCast(h))) {
                const uy: usize = @intCast(y_i);
                // Determine layering: later threads can overwrite
                // but only if they're "on top" (check phase ordering)
                const depth_phase: u8 = @truncate(
                    @as(u32, @intCast(x)) *% 5 +% ctx.tick +% @as(u32, offsets[thread_idx]),
                );
                const depth = math.sinF(depth_phase);

                const existing = cells[uy][x];
                if (existing.char == ' ' or depth > 0.5) {
                    cells[uy][x] = .{
                        .char = thread_chars[thread_idx],
                        .fg = thread_colors[thread_idx],
                        .bold = depth > 0.7 and ctx.intensity > 0.6,
                    };
                }
            }
        }
    }

    // Connection points where threads cross
    for (0..w) |x| {
        var occupied_rows: [3]?usize = .{ null, null, null };
        for (0..3) |t| {
            const phase: u8 = @truncate(
                @as(u32, @intCast(x)) *% @as(u32, freqs[t]) +%
                    ctx.tick *% 3 +%
                    @as(u32, offsets[t]),
            );
            const wave = math.sinFull(phase);
            const amplitude: f32 = @as(f32, @floatFromInt(h)) * 0.35 * ctx.intensity;
            const y_f = mid_y + wave * amplitude;
            const y_i: isize = @intFromFloat(y_f);
            if (y_i >= 0 and y_i < @as(isize, @intCast(h))) {
                occupied_rows[t] = @intCast(y_i);
            }
        }
        // If any two threads share the same row, mark as crossing
        for (0..3) |a| {
            for (a + 1..3) |b| {
                if (occupied_rows[a]) |ya| {
                    if (occupied_rows[b]) |yb| {
                        if (ya == yb) {
                            cells[ya][x] = .{
                                .char = 'X',
                                .fg = ctx.bright_color,
                                .bold = true,
                            };
                        }
                    }
                }
            }
        }
    }
}
