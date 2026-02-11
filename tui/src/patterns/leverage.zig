/// Leverage pattern: Balance/tilt — asymmetric lever arms oscillating
/// around a pivot point. Used by: Fulcrum.

const math = @import("../math.zig");
const portrait = @import("../portrait.zig");
const mod = @import("mod.zig");

pub fn generate(
    cells: *[portrait.max_h][portrait.max_w]portrait.PortraitCell,
    ctx: mod.PatternContext,
) void {
    const w = ctx.width;
    const h = ctx.height;

    // Clear
    for (0..h) |y| {
        for (0..w) |x| {
            cells[y][x] = .{ .char = ' ' };
        }
    }

    const pivot_x: f32 = @as(f32, @floatFromInt(w)) / 2.0;
    const pivot_y: f32 = @as(f32, @floatFromInt(h)) * 0.6;

    // Tilt angle oscillates
    const tilt_phase: u8 = @truncate(ctx.tick *% 2);
    const tilt = math.sinFull(tilt_phase) * 0.4 * ctx.intensity;

    // Draw the lever arm
    const arm_length: f32 = @as(f32, @floatFromInt(w)) * 0.4;
    for (0..w) |x| {
        const fx: f32 = @floatFromInt(x);
        const rel_x = fx - pivot_x;

        // y = pivot_y + rel_x * tilt
        const beam_y_f = pivot_y + rel_x * tilt;
        const beam_y: isize = @intFromFloat(beam_y_f);

        if (@abs(rel_x) <= arm_length) {
            if (beam_y >= 0 and beam_y < @as(isize, @intCast(h))) {
                const uy: usize = @intCast(beam_y);
                cells[uy][x] = .{
                    .char = '=',
                    .fg = ctx.primary_color,
                    .bold = true,
                };
            }
        }
    }

    // Pivot triangle
    const pivot_xi: usize = @intFromFloat(pivot_x);
    const pivot_yi: usize = @intFromFloat(pivot_y);
    if (pivot_yi + 1 < h and pivot_xi > 0 and pivot_xi + 1 < w) {
        cells[pivot_yi][pivot_xi] = .{ .char = '^', .fg = ctx.bright_color, .bold = true };
        if (pivot_yi + 1 < h) {
            cells[pivot_yi + 1][pivot_xi] = .{ .char = '|', .fg = ctx.bright_color, .bold = true };
        }
        if (pivot_yi + 2 < h and pivot_xi > 0 and pivot_xi + 1 < w) {
            cells[pivot_yi + 2][pivot_xi -| 1] = .{ .char = '/', .fg = ctx.primary_color };
            cells[pivot_yi + 2][pivot_xi] = .{ .char = '_', .fg = ctx.primary_color };
            cells[pivot_yi + 2][pivot_xi + 1] = .{ .char = '\\', .fg = ctx.primary_color };
        }
    }

    // Weight blocks on each end
    const left_end_x: isize = @intFromFloat(pivot_x - arm_length);
    const right_end_x: isize = @intFromFloat(pivot_x + arm_length);
    const left_y: isize = @intFromFloat(pivot_y + (-arm_length) * tilt);
    const right_y: isize = @intFromFloat(pivot_y + arm_length * tilt);

    drawWeight(cells, left_end_x, left_y, w, h, ctx.bright_color);
    drawWeight(cells, right_end_x, right_y, w, h, ctx.dim_color);
}

fn drawWeight(
    cells: *[portrait.max_h][portrait.max_w]portrait.PortraitCell,
    cx: isize, cy: isize,
    w: usize, h: usize,
    col: [3]u8,
) void {
    // 3x2 weight block
    const offsets = [_][2]isize{
        .{ -1, -1 }, .{ 0, -1 }, .{ 1, -1 },
        .{ -1, 0 },  .{ 0, 0 },  .{ 1, 0 },
    };
    const chars = [_]u8{
        '[', '#', ']',
        '[', '#', ']',
    };
    for (offsets, 0..) |off, i| {
        const px = cx + off[0];
        const py = cy + off[1];
        if (px >= 0 and py >= 0) {
            const ux: usize = @intCast(px);
            const uy: usize = @intCast(py);
            if (ux < w and uy < h) {
                cells[uy][ux] = .{
                    .char = chars[i],
                    .fg = col,
                    .bold = true,
                };
            }
        }
    }
}
