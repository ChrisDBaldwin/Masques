/// Structural pattern: Wireframe rotation — 3D shapes projected to 2D.
/// Used by: Parallax.
/// Simple rotating cube using /\|-_+X characters.

const math = @import("../math.zig");
const portrait = @import("../portrait.zig");
const mod = @import("mod.zig");

pub fn generate(
    cells: *[portrait.max_h][portrait.max_w]portrait.PortraitCell,
    ctx: mod.PatternContext,
) void {
    const w = ctx.width;
    const h = ctx.height;
    const cx: f32 = @as(f32, @floatFromInt(w)) / 2.0;
    const cy: f32 = @as(f32, @floatFromInt(h)) / 2.0;

    // Rotation angle from tick
    const angle_phase: u8 = @truncate(ctx.tick *% 1); // slow rotation

    // Clear
    for (0..h) |y| {
        for (0..w) |x| {
            cells[y][x] = .{ .char = ' ' };
        }
    }

    // Project 8 cube vertices and draw edges
    const size: f32 = @min(@as(f32, @floatFromInt(w)) * 0.3, @as(f32, @floatFromInt(h)) * 0.6);

    // Cube vertices in normalized space [-1, 1]
    const verts = [8][3]f32{
        .{ -1, -1, -1 }, .{ 1, -1, -1 }, .{ 1, 1, -1 }, .{ -1, 1, -1 },
        .{ -1, -1, 1 },  .{ 1, -1, 1 },  .{ 1, 1, 1 },  .{ -1, 1, 1 },
    };

    // Edges: pairs of vertex indices
    const edges = [12][2]u8{
        .{ 0, 1 }, .{ 1, 2 }, .{ 2, 3 }, .{ 3, 0 },
        .{ 4, 5 }, .{ 5, 6 }, .{ 6, 7 }, .{ 7, 4 },
        .{ 0, 4 }, .{ 1, 5 }, .{ 2, 6 }, .{ 3, 7 },
    };

    const cos_a = @as(f32, @floatFromInt(math.cosI(angle_phase))) / 127.0;
    const sin_a = @as(f32, @floatFromInt(math.sinI(angle_phase))) / 127.0;
    const tilt_phase: u8 = @truncate(ctx.tick *% 1 +% 64);
    const cos_b = @as(f32, @floatFromInt(math.cosI(tilt_phase))) / 127.0 * 0.5;
    const sin_b = @as(f32, @floatFromInt(math.sinI(tilt_phase))) / 127.0 * 0.5;

    // Project vertices to 2D
    var projected: [8][2]f32 = undefined;
    for (0..8) |i| {
        const vx = verts[i][0];
        const vy = verts[i][1];
        const vz = verts[i][2];

        // Rotate around Y axis
        const rx = vx * cos_a + vz * sin_a;
        const ry = vy;
        const rz = -vx * sin_a + vz * cos_a;

        // Tilt around X axis
        const ry2 = ry * (0.8 + cos_b * 0.2) - rz * sin_b;
        const rz2 = ry * sin_b + rz * (0.8 + cos_b * 0.2);
        _ = rz2;

        // Perspective projection
        projected[i][0] = cx + rx * size * ctx.intensity;
        projected[i][1] = cy + ry2 * size * 0.5 * ctx.intensity; // half for aspect
    }

    // Draw edges using Bresenham-ish line
    for (edges) |edge| {
        const x0 = projected[edge[0]][0];
        const y0 = projected[edge[0]][1];
        const x1 = projected[edge[1]][0];
        const y1 = projected[edge[1]][1];

        drawLine(cells, x0, y0, x1, y1, w, h, ctx.primary_color, ctx.intensity);
    }

    // Vertices as bright dots
    for (0..8) |i| {
        const px: isize = @intFromFloat(projected[i][0]);
        const py: isize = @intFromFloat(projected[i][1]);
        if (px >= 0 and py >= 0) {
            const ux: usize = @intCast(px);
            const uy: usize = @intCast(py);
            if (ux < w and uy < h) {
                cells[uy][ux] = .{
                    .char = '+',
                    .fg = ctx.bright_color,
                    .bold = true,
                };
            }
        }
    }
}

fn drawLine(
    cells: *[portrait.max_h][portrait.max_w]portrait.PortraitCell,
    x0: f32, y0: f32, x1: f32, y1: f32,
    w: usize, h: usize,
    col: [3]u8, intensity: f32,
) void {
    const steps: usize = @intFromFloat(@max(@abs(x1 - x0), @abs(y1 - y0)) + 1);
    if (steps == 0) return;
    for (0..@min(steps, 100)) |i| {
        const t = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(steps));
        const px: isize = @intFromFloat(math.lerp(x0, x1, t));
        const py: isize = @intFromFloat(math.lerp(y0, y1, t));
        if (px >= 0 and py >= 0) {
            const ux: usize = @intCast(px);
            const uy: usize = @intCast(py);
            if (ux < w and uy < h) {
                // Choose line char based on slope
                const dx = x1 - x0;
                const dy = y1 - y0;
                const char: u8 = if (@abs(dx) > @abs(dy) * 2.0) '-' else if (@abs(dy) > @abs(dx) * 2.0) '|' else if (dx * dy > 0) '\\' else '/';
                cells[uy][ux] = .{
                    .char = char,
                    .fg = col,
                    .bold = intensity > 0.7,
                };
            }
        }
    }
}

const math_import = @import("../math.zig");
const lerp = math_import.lerp;
