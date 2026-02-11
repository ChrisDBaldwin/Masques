/// Cybernetic pattern: Feedback loops — concentric rings that pulse in/out.
/// Used by: Steersman.
/// Rings of bracket characters (){}[]<> that breathe and orbit.

const math = @import("../math.zig");
const gradient = @import("../gradient.zig");
const portrait = @import("../portrait.zig");
const color = @import("../color.zig");
const mod = @import("mod.zig");

pub fn generate(
    cells: *[portrait.max_h][portrait.max_w]portrait.PortraitCell,
    ctx: mod.PatternContext,
) void {
    const w = ctx.width;
    const h = ctx.height;
    const cx: f32 = @as(f32, @floatFromInt(w)) / 2.0;
    const cy: f32 = @as(f32, @floatFromInt(h)) / 2.0;

    // Ring characters for each concentric level
    const ring_chars = [_][2]u8{ .{ '(', ')' }, .{ '[', ']' }, .{ '{', '}' }, .{ '<', '>' } };

    // Pulsing radius offset
    const pulse_phase: u8 = @truncate(ctx.tick *% 4);
    const pulse = math.sinFull(pulse_phase) * 0.8 * ctx.intensity;

    // Orbiting sensor dot
    const orbit_phase: u8 = @truncate(ctx.tick *% 2);
    const orbit_r: f32 = 2.5 + pulse * 0.5;
    const sensor_x = cx + @as(f32, @floatFromInt(math.cosI(orbit_phase))) / 127.0 * orbit_r * 2.0; // wider for aspect
    const sensor_y = cy + @as(f32, @floatFromInt(math.sinI(orbit_phase))) / 127.0 * orbit_r;

    for (0..h) |y| {
        for (0..w) |x| {
            const fx: f32 = @floatFromInt(x);
            const fy: f32 = @floatFromInt(y);

            // Aspect-corrected distance from center
            const dx = (fx - cx) / 2.0; // terminals are ~2:1 aspect
            const dy = fy - cy;
            const dist = @sqrt(dx * dx + dy * dy);

            // Determine which ring this cell is on
            const ring_dist = dist + pulse;
            const ring_idx_f = ring_dist * 1.5;
            const ring_idx: usize = @intFromFloat(@max(0.0, @min(ring_idx_f, 20.0)));

            // Check if we're near a ring boundary
            const frac = ring_idx_f - @as(f32, @floatFromInt(ring_idx));
            const on_ring = (frac < 0.2 or frac > 0.8);

            // Sensor dot
            const sdx = fx - sensor_x;
            const sdy = fy - sensor_y;
            const sensor_dist = @sqrt(sdx * sdx + sdy * sdy);

            if (sensor_dist < 1.0) {
                cells[y][x] = .{
                    .char = '@',
                    .fg = ctx.bright_color,
                    .bold = true,
                };
            } else if (on_ring and ring_idx < 8) {
                // Pick bracket pair based on ring
                const pair_idx = (ring_idx / 2) % ring_chars.len;
                const pair = ring_chars[pair_idx];

                // Left or right half determines open/close bracket
                const char = if (fx < cx) pair[0] else pair[1];

                const ring_intensity = @max(0.0, 1.0 - @as(f32, @floatFromInt(ring_idx)) / 8.0);
                const fg = if (ring_intensity * ctx.intensity > 0.6)
                    ctx.bright_color
                else if (ring_intensity * ctx.intensity > 0.3)
                    ctx.primary_color
                else
                    ctx.dim_color;

                cells[y][x] = .{
                    .char = char,
                    .fg = fg,
                    .bold = ring_intensity > 0.5,
                };
            } else {
                // Fill space with subtle connectors
                const flow_phase: u8 = @truncate(ctx.tick +% @as(u32, @intCast(x +% y * 3)));
                const flow = math.sinF(flow_phase);
                if (flow > 0.85 and ctx.intensity > 0.4) {
                    const connector = if (@as(u8, @truncate(@as(u32, @intCast(x +% y)))) & 1 == 0) @as(u8, '-') else @as(u8, '~');
                    cells[y][x] = .{
                        .char = connector,
                        .fg = ctx.dim_color,
                    };
                } else {
                    cells[y][x] = .{ .char = ' ' };
                }
            }
        }
    }
}
