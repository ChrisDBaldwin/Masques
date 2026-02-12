/// Detail panel: theatrical mask portrait + full metadata for the selected masque.
/// The portrait area renders a domain-animated pattern composited through an
/// elliptical mask shape with diamond eye cutouts.
/// All text uses string literals or allocator-owned slices — no stack-local
/// bufPrint, which would create dangling pointers in the vaxis cell buffer.

const std = @import("std");
const vaxis = @import("vaxis");
const masque_mod = @import("masque.zig");
const portrait_mod = @import("portrait.zig");
const color_mod = @import("color.zig");
const state_mod = @import("state.zig");
const layout_mod = @import("layout.zig");
const mask_mod = @import("mask.zig");
const patterns = @import("patterns/mod.zig");
const math = @import("math.zig");

pub fn render(
    win: vaxis.Window,
    app: *const state_mod.AppState,
    lo: *const layout_mod.Layout,
) void {
    _ = lo;

    // Guard: need at least some space to render
    if (win.width < 4 or win.height < 4) return;

    const masque_idx = app.cursorMasqueIndex() orelse {
        const seg: vaxis.Segment = .{
            .text = "Select a masque",
            .style = .{ .fg = .{ .rgb = .{ 100, 100, 100 } } },
        };
        _ = win.print(&.{seg}, .{ .row_offset = @intCast(win.height / 2), .col_offset = 2 });
        return;
    };

    const m = &app.masques[masque_idx];
    const colors = color_mod.domainColors(m.domain);

    // No explicit background fill — let the terminal's native background show through

    // Large portrait area at top — mask-composited
    const portrait_h: usize = @min(portrait_mod.large_h, @as(usize, win.height) / 3);
    const portrait_w: usize = @min(portrait_mod.large_w, @as(usize, win.width) -| 2);

    if (masque_idx < app.portraits.len and portrait_h >= 3 and portrait_w >= 3) {
        const p = &app.portraits[masque_idx];

        // Portrait border — create child window first to get inner dimensions
        const portrait_win = win.child(.{
            .x_off = 1,
            .y_off = 0,
            .width = @intCast(portrait_w),
            .height = @intCast(portrait_h),
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .rgb = colors.primary } },
                .glyphs = .{ .custom = .{ "\u{2554}", "\u{2550}", "\u{2557}", "\u{2551}", "\u{255d}", "\u{255a}" } },
            },
        });

        // Use inner dimensions (content area inside border) for pattern + mask
        const inner_w: usize = if (portrait_win.width > 0) portrait_win.width else 0;
        const inner_h: usize = if (portrait_win.height > 0) portrait_win.height else 0;

        if (inner_w >= 3 and inner_h >= 3) {
            // Generate pattern at inner dimensions
            var cells: [portrait_mod.max_h][portrait_mod.max_w]portrait_mod.PortraitCell = undefined;
            for (0..portrait_mod.max_h) |y| {
                for (0..portrait_mod.max_w) |x| {
                    cells[y][x] = .{};
                }
            }

            const ctx = patterns.PatternContext{
                .width = inner_w,
                .height = inner_h,
                .tick = p.tick,
                .seed = p.seed,
                .intensity = p.intensity(),
                .primary_color = p.primary_color,
                .dim_color = p.dim_color,
                .bright_color = p.bright_color,
                .domain_category = p.domain_category,
            };
            p.pattern(&cells, ctx);

            // Apply background tinting (matches portrait.update post-processing)
            {
                const bg_intensity: f32 = switch (p.state) {
                    .idle => 0.08,
                    .selecting => 0.12,
                    .selected => 0.15,
                    .deselecting => 0.08,
                    .confirming => if (p.state_tick < 5) 0.3 else 0.1,
                };
                for (0..inner_h) |y| {
                    for (0..inner_w) |x| {
                        if (cells[y][x].char != ' ') {
                            cells[y][x].bg = color_mod.dimColor(p.primary_color, bg_intensity);
                        } else {
                            cells[y][x].bg = color_mod.dimColor(p.primary_color, bg_intensity * 0.3);
                        }
                    }
                }
            }

            // Eye glow pulse: subtle brightness oscillation
            const eye_phase: u8 = @truncate(p.tick *% 4);
            const eye_glow = math.sinFull(eye_phase) * 0.3 + 0.15;
            const eye_r: u8 = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(colors.primary[0])) * eye_glow, 0.0, 255.0));
            const eye_g: u8 = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(colors.primary[1])) * eye_glow, 0.0, 255.0));
            const eye_b: u8 = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(colors.primary[2])) * eye_glow, 0.0, 255.0));

            // Map category to mask shape
            const mask_shape: mask_mod.Shape = switch (m.category) {
                .executive => .sovereign,
                .cognitive => .cerebral,
                .art => .theatrical,
                .meta => .geometric,
                .specialist, .all => .classic,
            };

            // Composite through mask zones into the bordered child window
            for (0..inner_h) |y| {
                for (0..inner_w) |x| {
                    const zone = mask_mod.classify(x, y, inner_w, inner_h, mask_shape);
                    switch (zone) {
                        .face => {
                            const pc = cells[y][x];
                            const idx: usize = if (pc.char < 128) pc.char else ' ';
                            portrait_win.writeCell(@intCast(x), @intCast(y), .{
                                .char = .{ .grapheme = &portrait_mod.Portrait.ascii_table[idx], .width = 1 },
                                .style = .{
                                    .fg = .{ .rgb = pc.fg },
                                    .bg = .{ .rgb = pc.bg },
                                    .bold = pc.bold,
                                },
                            });
                        },
                        .border => {
                            const pc = cells[y][x];
                            const boost: f32 = 1.4;
                            const fg_r: u8 = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(pc.fg[0])) * boost, 0.0, 255.0));
                            const fg_g: u8 = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(pc.fg[1])) * boost, 0.0, 255.0));
                            const fg_b: u8 = @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(pc.fg[2])) * boost, 0.0, 255.0));
                            const idx: usize = if (pc.char < 128) pc.char else ' ';
                            portrait_win.writeCell(@intCast(x), @intCast(y), .{
                                .char = .{ .grapheme = &portrait_mod.Portrait.ascii_table[idx], .width = 1 },
                                .style = .{
                                    .fg = .{ .rgb = .{ fg_r, fg_g, fg_b } },
                                    .bg = .{ .rgb = color_mod.dimColor(colors.primary, 0.2) },
                                    .bold = true,
                                },
                            });
                        },
                        .eye_left, .eye_right => {
                            portrait_win.writeCell(@intCast(x), @intCast(y), .{
                                .char = .{ .grapheme = " ", .width = 1 },
                                .style = .{
                                    .bg = .{ .rgb = .{ eye_r, eye_g, eye_b } },
                                },
                            });
                        },
                        .outside => {
                            // Default bg — let the terminal background show through
                        },
                    }
                }
            }
        }
    }

    // Metadata below portrait — saturating adds prevent overflow
    var row: u16 = @intCast(portrait_h +| 1);

    // Name + " v" + version
    {
        const name_seg: vaxis.Segment = .{
            .text = m.name,
            .style = .{ .fg = .{ .rgb = colors.bright }, .bold = true },
        };
        const v_seg: vaxis.Segment = .{
            .text = " v",
            .style = .{ .fg = .{ .rgb = colors.primary } },
        };
        const ver_seg: vaxis.Segment = .{
            .text = m.version,
            .style = .{ .fg = .{ .rgb = colors.primary } },
        };
        _ = win.print(&.{ name_seg, v_seg, ver_seg }, .{ .row_offset = row, .col_offset = 1 });
        row +|= 1;
    }

    // Domain + category badge + source badge
    {
        const domain_seg: vaxis.Segment = .{
            .text = m.domain,
            .style = .{ .fg = .{ .rgb = colors.primary } },
        };
        const sep_seg: vaxis.Segment = .{
            .text = "  ",
            .style = .{},
        };
        const cat_seg: vaxis.Segment = .{
            .text = m.category.label(),
            .style = .{ .fg = .{ .rgb = .{ 120, 120, 120 } }, .italic = true },
        };
        const source_sep: vaxis.Segment = .{
            .text = "  ",
            .style = .{},
        };
        const source_color: [3]u8 = if (m.source == .private) .{ 180, 130, 255 } else .{ 100, 100, 100 };
        const source_text: []const u8 = if (m.source == .private) "[private]" else "[shared]";
        const source_seg: vaxis.Segment = .{
            .text = source_text,
            .style = .{ .fg = .{ .rgb = source_color }, .italic = true },
        };
        _ = win.print(&.{ domain_seg, sep_seg, cat_seg, source_sep, source_seg }, .{ .row_offset = row, .col_offset = 1 });
        row +|= 1;
    }

    // Tagline
    if (m.tagline.len > 0) {
        const q_style: vaxis.Style = .{ .fg = .{ .rgb = .{ 200, 200, 200 } }, .italic = true };
        const q1: vaxis.Segment = .{ .text = "\u{201c}", .style = q_style };
        const tag_seg: vaxis.Segment = .{ .text = m.tagline, .style = q_style };
        const q2: vaxis.Segment = .{ .text = "\u{201d}", .style = q_style };
        _ = win.print(&.{ q1, tag_seg, q2 }, .{ .row_offset = row, .col_offset = 1 });
        row +|= 1;
    }

    // Separator
    if (row < win.height) {
        const sep_style: vaxis.Style = .{ .fg = .{ .rgb = color_mod.dimColor(colors.primary, 0.3) } };
        const sep_seg: vaxis.Segment = .{ .text = "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}", .style = sep_style };
        _ = win.print(&.{sep_seg}, .{ .row_offset = row, .col_offset = 1 });
        row +|= 1;
    }

    // Style + Philosophy combined on one row
    {
        const has_style = m.style.len > 0;
        const has_phil = m.philosophy.len > 0;
        const body_color: [3]u8 = .{ 200, 200, 200 };
        if ((has_style or has_phil) and row < win.height) {
            if (has_style and has_phil) {
                const label_style: vaxis.Style = .{ .fg = .{ .rgb = .{ 180, 180, 180 } }, .bold = true };
                const val_style: vaxis.Style = .{ .fg = .{ .rgb = body_color } };
                const max_style = @min(m.style.len, @as(usize, win.width) / 2 -| 10);
                const max_phil = @min(m.philosophy.len, @as(usize, win.width) / 2 -| 14);
                const segs = [_]vaxis.Segment{
                    .{ .text = "Style: ", .style = label_style },
                    .{ .text = m.style[0..max_style], .style = val_style },
                    .{ .text = "  \u{2502}  ", .style = .{ .fg = .{ .rgb = .{ 100, 100, 100 } } } },
                    .{ .text = "Philosophy: ", .style = label_style },
                    .{ .text = m.philosophy[0..max_phil], .style = val_style },
                };
                _ = win.print(&segs, .{ .row_offset = row, .col_offset = 1 });
            } else if (has_style) {
                printLabelValue(win, row, "Style: ", m.style, body_color);
            } else {
                printLabelValue(win, row, "Philosophy: ", m.philosophy, body_color);
            }
            row +|= 1;
        }
    }

    // Separator before lens/context
    if (row < win.height and (m.lens.len > 0 or m.context.len > 0)) {
        const sep_style2: vaxis.Style = .{ .fg = .{ .rgb = color_mod.dimColor(colors.primary, 0.3) } };
        const sep_seg2: vaxis.Segment = .{ .text = "\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}\u{2500}", .style = sep_style2 };
        _ = win.print(&.{sep_seg2}, .{ .row_offset = row, .col_offset = 1 });
        row +|= 1;
    }

    // Context (word-wrapped)
    if (m.context.len > 0 and row < win.height) {
        const ctx_label: vaxis.Segment = .{
            .text = "Context",
            .style = .{ .fg = .{ .rgb = .{ 180, 180, 180 } }, .bold = true },
        };
        _ = win.print(&.{ctx_label}, .{ .row_offset = row, .col_offset = 1 });
        row +|= 1;

        const avail_w_ctx: usize = @as(usize, win.width) -| 3;
        // Give context a fair share of remaining space, but reserve room for lens
        const remaining: usize = @as(usize, win.height) -| row;
        const ctx_max_rows: usize = if (m.lens.len > 0)
            remaining / 2
        else
            remaining -| 1;
        const ctx_style: vaxis.Style = .{ .fg = .{ .rgb = .{ 200, 200, 200 } } };
        row +|= renderWrappedText(win, row, 2, avail_w_ctx, ctx_max_rows, m.context, ctx_style);
        row +|= 1;
    }

    // Lens (word-wrapped)
    if (m.lens.len > 0 and row < win.height) {
        const label_seg: vaxis.Segment = .{
            .text = "Lens",
            .style = .{ .fg = .{ .rgb = .{ 180, 180, 180 } }, .bold = true },
        };
        _ = win.print(&.{label_seg}, .{ .row_offset = row, .col_offset = 1 });
        row +|= 1;

        const avail_w: usize = @as(usize, win.width) -| 3;
        const max_rows: usize = @as(usize, win.height) -| row;
        const lens_style: vaxis.Style = .{ .fg = .{ .rgb = .{ 220, 220, 220 } } };
        row +|= renderWrappedText(win, row, 2, avail_w, max_rows, m.lens, lens_style);
    } else if (m.lens_summary.len > 0 and row < win.height) {
        // Fallback to summary if full lens not loaded
        const label_seg: vaxis.Segment = .{
            .text = "Lens: ",
            .style = .{ .fg = .{ .rgb = .{ 180, 180, 180 } }, .bold = true },
        };
        const max_val = @min(m.lens_summary.len, @as(usize, win.width) -| 8);
        const val_seg: vaxis.Segment = .{
            .text = m.lens_summary[0..max_val],
            .style = .{ .fg = .{ .rgb = .{ 220, 220, 220 } } },
        };
        _ = win.print(&.{ label_seg, val_seg }, .{ .row_offset = row, .col_offset = 1 });
    }
}

/// Render word-wrapped text into the window. Handles explicit newlines and
/// word-boundary wrapping. Returns the number of rows consumed.
fn renderWrappedText(
    win: vaxis.Window,
    start_row: u16,
    col_offset: u16,
    max_width: usize,
    max_rows: usize,
    text: []const u8,
    style: vaxis.Style,
) u16 {
    if (max_width < 2 or max_rows == 0) return 0;

    var rows_used: u16 = 0;
    var pos: usize = 0;

    while (pos < text.len and rows_used < max_rows) {
        // Skip leading whitespace (but not newlines)
        while (pos < text.len and text[pos] == ' ') : (pos += 1) {}

        // Handle explicit newlines
        if (pos < text.len and text[pos] == '\n') {
            pos += 1;
            rows_used +|= 1;
            continue;
        }

        if (pos >= text.len) break;

        // Find the end of this line: either max_width chars or a newline
        var line_end = pos;
        var last_space: ?usize = null;
        var col: usize = 0;

        while (line_end < text.len and text[line_end] != '\n' and col < max_width) {
            if (text[line_end] == ' ') {
                last_space = line_end;
            }
            line_end += 1;
            col += 1;
        }

        // If we hit the width limit and didn't end at a space, break at last space
        if (col >= max_width and line_end < text.len and text[line_end] != '\n') {
            if (last_space) |sp| {
                if (sp > pos) {
                    line_end = sp;
                }
            }
        }

        // Trim the line slice
        const line = std.mem.trimRight(u8, text[pos..line_end], " ");
        if (line.len > 0) {
            const current_row = start_row +| rows_used;
            if (current_row >= win.height) break;
            const seg: vaxis.Segment = .{ .text = line, .style = style };
            _ = win.print(&.{seg}, .{ .row_offset = current_row, .col_offset = col_offset });
        }

        rows_used +|= 1;
        pos = line_end;
        // Skip the space we broke on
        if (pos < text.len and text[pos] == ' ') pos += 1;
    }

    return rows_used;
}

fn printLabelValue(win: vaxis.Window, row: u16, label_text: []const u8, value: []const u8, col: [3]u8) void {
    const label_seg: vaxis.Segment = .{
        .text = label_text,
        .style = .{ .fg = .{ .rgb = .{ 180, 180, 180 } }, .bold = true },
    };
    const max_val = @min(value.len, @as(usize, win.width) -| (label_text.len +| 2));
    const val_seg: vaxis.Segment = .{
        .text = value[0..max_val],
        .style = .{ .fg = .{ .rgb = col } },
    };
    _ = win.print(&.{ label_seg, val_seg }, .{ .row_offset = row, .col_offset = 1 });
}
