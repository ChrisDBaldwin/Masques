/// Mask geometry: spatial classification for theatrical mask portrait rendering.
/// Five distinct mask silhouettes mapped to masque categories.
/// Pure math — no rendering, no allocations. All coordinates proportional to
/// width/height so the mask scales to any size.

const std = @import("std");

pub const Zone = enum {
    face,
    eye_left,
    eye_right,
    border,
    outside,
};

/// Mask silhouette. Each category gets a distinct shape.
pub const Shape = enum {
    classic, // specialist — balanced theatrical mask, almond eyes
    sovereign, // executive — wide angular, strong brow, narrow slit eyes
    cerebral, // cognitive — domed forehead, narrow chin, tall round eyes
    theatrical, // art — asymmetric, one eye larger, organic curves
    geometric, // meta — perfect circle, small round eyes, minimal
};

const ShapeParams = struct {
    // Face ellipse: rx interpolates from rx_top to rx_bottom below center
    rx_top: f32,
    rx_bottom: f32,
    ry: f32,
    // Eyes: positioned at (+-eye_spread, eye_y)
    eye_y: f32,
    eye_spread: f32,
    eye_w: f32, // horizontal radius
    eye_h: f32, // vertical radius
    eye_round: bool, // true = L2 (round), false = L1 (diamond)
    // Border band: cells where dist_sq > this are border (face = below it)
    border_sq: f32,
    // Art asymmetry: right eye offset from left
    asym_eye_w: f32, // 0 = symmetric, >0 = right eye differs
    asym_eye_h: f32,
    asym_eye_dy: f32, // right eye vertical shift
};

fn shapeParams(shape: Shape) ShapeParams {
    return switch (shape) {
        // Specialist: classic theatrical mask. Almond diamond eyes, gentle chin taper.
        .classic => .{
            .rx_top = 0.95,
            .rx_bottom = 0.70,
            .ry = 0.95,
            .eye_y = -0.25,
            .eye_spread = 0.32,
            .eye_w = 0.14,
            .eye_h = 0.18,
            .eye_round = false,
            .border_sq = 0.72,
            .asym_eye_w = 0,
            .asym_eye_h = 0,
            .asym_eye_dy = 0,
        },
        // Executive: wide power mask. Flat brow, strong angular jaw, narrow slit eyes.
        .sovereign => .{
            .rx_top = 0.98,
            .rx_bottom = 0.52,
            .ry = 0.92,
            .eye_y = -0.18,
            .eye_spread = 0.34,
            .eye_w = 0.18,
            .eye_h = 0.10,
            .eye_round = false,
            .border_sq = 0.68,
            .asym_eye_w = 0,
            .asym_eye_h = 0,
            .asym_eye_dy = 0,
        },
        // Cognitive: domed forehead, narrow pointed chin. Tall round eyes set high.
        .cerebral => .{
            .rx_top = 0.88,
            .rx_bottom = 0.38,
            .ry = 0.95,
            .eye_y = -0.30,
            .eye_spread = 0.28,
            .eye_w = 0.12,
            .eye_h = 0.22,
            .eye_round = true,
            .border_sq = 0.74,
            .asym_eye_w = 0,
            .asym_eye_h = 0,
            .asym_eye_dy = 0,
        },
        // Art: asymmetric, organic. Left eye larger and higher than right.
        .theatrical => .{
            .rx_top = 0.90,
            .rx_bottom = 0.62,
            .ry = 0.95,
            .eye_y = -0.22,
            .eye_spread = 0.30,
            .eye_w = 0.16,
            .eye_h = 0.20,
            .eye_round = false,
            .asym_eye_w = 0.11, // right eye narrower
            .asym_eye_h = 0.14, // right eye shorter
            .asym_eye_dy = 0.08, // right eye lower
            .border_sq = 0.70,
        },
        // Meta: perfect circle, small round eyes, geometric precision.
        .geometric => .{
            .rx_top = 0.82,
            .rx_bottom = 0.82, // no chin taper — circle
            .ry = 0.82,
            .eye_y = -0.20,
            .eye_spread = 0.28,
            .eye_w = 0.10,
            .eye_h = 0.10,
            .eye_round = true,
            .border_sq = 0.70,
            .asym_eye_w = 0,
            .asym_eye_h = 0,
            .asym_eye_dy = 0,
        },
    };
}

/// Classify a cell position into a mask zone.
/// Coordinates are cell positions (0-based), width/height are the total area.
pub fn classify(x: usize, y: usize, width: usize, height: usize, shape: Shape) Zone {
    if (width < 3 or height < 3) return .outside;

    const sp = shapeParams(shape);

    // Normalize to [-1, 1] with center at (0, 0)
    const fw: f32 = @floatFromInt(width);
    const fh: f32 = @floatFromInt(height);
    const nx: f32 = (@as(f32, @floatFromInt(x)) + 0.5 - fw / 2.0) / (fw / 2.0);
    const ny: f32 = (@as(f32, @floatFromInt(y)) + 0.5 - fh / 2.0) / (fh / 2.0);

    // Left eye
    {
        const dx = @abs(nx - (-sp.eye_spread)) / sp.eye_w;
        const dy = @abs(ny - sp.eye_y) / sp.eye_h;
        const dist = if (sp.eye_round) dx * dx + dy * dy else dx + dy;
        if (dist < 1.0) return .eye_left;
    }

    // Right eye (may be asymmetric for theatrical shape)
    {
        const rw = if (sp.asym_eye_w > 0) sp.asym_eye_w else sp.eye_w;
        const rh = if (sp.asym_eye_h > 0) sp.asym_eye_h else sp.eye_h;
        const ry_pos = sp.eye_y + sp.asym_eye_dy;
        const dx = @abs(nx - sp.eye_spread) / rw;
        const dy = @abs(ny - ry_pos) / rh;
        const dist = if (sp.eye_round) dx * dx + dy * dy else dx + dy;
        if (dist < 1.0) return .eye_right;
    }

    // Face outline: ellipse that tapers from rx_top to rx_bottom below center
    const rx: f32 = if (ny > 0.0)
        sp.rx_top - (sp.rx_top - sp.rx_bottom) * ny // linear taper toward chin
    else
        sp.rx_top;

    const ex = nx / rx;
    const ey = ny / sp.ry;
    const dist_sq = ex * ex + ey * ey;

    if (dist_sq > 1.0) return .outside;
    if (dist_sq > sp.border_sq) return .border;
    return .face;
}
