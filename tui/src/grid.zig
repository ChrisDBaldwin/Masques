/// Grid rendering: portrait cards arranged in dynamic columns.

const std = @import("std");
const vaxis = @import("vaxis");
const masque_mod = @import("masque.zig");
const portrait_mod = @import("portrait.zig");
const color_mod = @import("color.zig");
const layout_mod = @import("layout.zig");
const state_mod = @import("state.zig");

/// Render the grid of portrait cards into the given window.
pub fn render(
    win: vaxis.Window,
    app: *const state_mod.AppState,
    lo: *const layout_mod.Layout,
) void {
    // Filter visible masques
    var visible_indices: [64]usize = undefined;
    var visible_count: usize = 0;
    for (app.masques, 0..) |m, i| {
        if (app.active_tab == .all or m.category == app.active_tab) {
            if (visible_count < 64) {
                visible_indices[visible_count] = i;
                visible_count += 1;
            }
        }
    }

    if (visible_count == 0) {
        const seg: vaxis.Segment = .{
            .text = "(no masques in this category)",
            .style = .{ .fg = .{ .rgb = .{ 100, 100, 100 } } },
        };
        _ = win.print(&.{seg}, .{ .row_offset = 1, .col_offset = 2 });
        return;
    }

    const cols = lo.grid_cols;

    for (visible_indices[0..visible_count], 0..) |masque_idx, vi| {
        const col = vi % cols;
        const row = vi / cols;

        const card_x = col * layout_mod.card_outer_w;
        const card_y = row * layout_mod.card_outer_h;

        // Skip if off-screen
        if (card_y + layout_mod.card_outer_h > win.height) continue;
        if (card_x + layout_mod.card_outer_w > win.width) continue;

        const m = &app.masques[masque_idx];
        const is_cursor = (vi == app.grid_cursor);
        const is_on_team = isOnTeam(m.name, app);
        const is_complement = isComplement(m.name, app);

        // Choose border style
        const colors = color_mod.domainColors(m.domain);
        const border_color: [3]u8 = if (is_cursor)
            .{ 255, 255, 255 }
        else if (is_complement)
            .{ 255, 215, 0 }
        else if (is_on_team)
            colors.bright
        else
            colors.primary;

        const border_glyphs: vaxis.Window.BorderOptions.Glyphs = if (is_cursor)
            .{ .custom = .{ "╔", "═", "╗", "║", "╝", "╚" } }
        else
            .single_rounded;

        const card = win.child(.{
            .x_off = @intCast(card_x),
            .y_off = @intCast(card_y),
            .width = @intCast(layout_mod.card_outer_w),
            .height = @intCast(layout_mod.card_outer_h),
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .rgb = border_color } },
                .glyphs = border_glyphs,
            },
        });

        // Fill card background with dark domain tint
        {
            const bg_tint = color_mod.dimColor(colors.primary, if (is_cursor) 0.12 else if (is_on_team) 0.08 else 0.04);
            const bg_color: vaxis.Color = .{ .rgb = bg_tint };
            for (0..card.height) |cy| {
                for (0..card.width) |cx| {
                    card.writeCell(@intCast(cx), @intCast(cy), .{
                        .char = .{ .grapheme = " ", .width = 1 },
                        .style = .{ .bg = bg_color },
                    });
                }
            }
        }

        // Render portrait inside the card (border takes 1 cell on each side)
        if (masque_idx < app.portraits.len) {
            app.portraits[masque_idx].render(card);
        }

        // Name label at bottom of card content area
        const name_y = if (card.height > 1) card.height - 1 else 0;
        const name_max = @min(m.name.len, card.width);
        const name_x = if (card.width > name_max) (card.width - name_max) / 2 else 0;

        const bg_for_name = color_mod.dimColor(colors.primary, if (is_cursor) 0.15 else 0.06);
        const name_style: vaxis.Style = .{
            .fg = .{ .rgb = if (is_cursor) colors.bright else colors.primary },
            .bg = .{ .rgb = bg_for_name },
            .bold = is_cursor or is_on_team,
        };
        const seg: vaxis.Segment = .{
            .text = m.name[0..name_max],
            .style = name_style,
        };
        _ = card.print(&.{seg}, .{
            .row_offset = @intCast(name_y),
            .col_offset = @intCast(name_x),
        });

        // Team indicator (gold *) and private indicator (lavender ~)
        if (is_on_team) {
            const indicator_style: vaxis.Style = .{
                .fg = .{ .rgb = .{ 255, 215, 0 } },
                .bold = true,
            };
            const ind: vaxis.Segment = .{ .text = "*", .style = indicator_style };
            _ = card.print(&.{ind}, .{
                .row_offset = 0,
                .col_offset = @intCast(if (card.width > 1) card.width - 1 else 0),
            });
        } else if (m.source == .private) {
            const priv_style: vaxis.Style = .{
                .fg = .{ .rgb = .{ 180, 130, 255 } },
                .bold = true,
            };
            const priv_ind: vaxis.Segment = .{ .text = "~", .style = priv_style };
            _ = card.print(&.{priv_ind}, .{
                .row_offset = 0,
                .col_offset = @intCast(if (card.width > 1) card.width - 1 else 0),
            });
        }
    }
}

fn isOnTeam(name: []const u8, app: *const state_mod.AppState) bool {
    for (app.team[0..app.team_count]) |slot| {
        if (slot) |member| {
            if (std.mem.eql(u8, member.name, name)) return true;
        }
    }
    return false;
}

fn isComplement(name: []const u8, app: *const state_mod.AppState) bool {
    const cursor_idx = app.cursorMasqueIndex() orelse return false;
    const complement = masque_mod.findComplement(app.masques[cursor_idx].name) orelse return false;
    return std.mem.eql(u8, name, complement);
}
