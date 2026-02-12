/// Dynamic layout calculator — computes panel regions from terminal size.

const portrait_mod = @import("portrait.zig");

pub const card_outer_w: usize = portrait_mod.thumb_w + 2; // portrait + border
pub const card_outer_h: usize = portrait_mod.thumb_h + 3; // portrait + border + name row

pub const Layout = struct {
    // Terminal dimensions
    term_w: usize,
    term_h: usize,

    // Title bar: row 0
    title_y: usize,
    title_h: usize,

    // Tab bar: row 1-2
    tabs_y: usize,
    tabs_h: usize,

    // Grid area (left)
    grid_x: usize,
    grid_y: usize,
    grid_w: usize,
    grid_h: usize,
    grid_cols: usize,
    grid_rows: usize,

    // Detail panel (right)
    detail_x: usize,
    detail_y: usize,
    detail_w: usize,
    detail_h: usize,

    // Roster (bottom)
    roster_y: usize,
    roster_h: usize,
    roster_w: usize,
};

pub fn compute(term_w: usize, term_h: usize) Layout {
    // Reserve rows: title(1) + tabs(1) + roster(8) + help(1) = 11
    const reserved_h: usize = 11;
    const middle_h = if (term_h > reserved_h) term_h - reserved_h else 4;

    // Detail panel: ~35% of width, minimum 28
    const detail_min: usize = 28;
    const detail_w = @max(detail_min, term_w * 35 / 100);

    // Grid area gets the rest
    const grid_w = if (term_w > detail_w + 2) term_w - detail_w else term_w / 2;

    // Grid columns: how many cards fit
    const grid_cols = @max(1, grid_w / card_outer_w);
    const grid_rows = @max(1, middle_h / card_outer_h);

    return .{
        .term_w = term_w,
        .term_h = term_h,

        .title_y = 0,
        .title_h = 1,

        .tabs_y = 1,
        .tabs_h = 1,

        .grid_x = 0,
        .grid_y = 2,
        .grid_w = grid_w,
        .grid_h = middle_h,
        .grid_cols = grid_cols,
        .grid_rows = grid_rows,

        .detail_x = grid_w,
        .detail_y = 2,
        .detail_w = detail_w,
        .detail_h = middle_h,

        .roster_y = if (term_h > 8) term_h - 8 else term_h -| 1,
        .roster_h = @min(8, term_h),
        .roster_w = term_w,
    };
}
