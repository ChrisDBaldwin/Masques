/// Team roster panel — bottom strip showing team slots.
/// All text uses string literals or allocator-owned slices — no stack-local
/// bufPrint, which would create dangling pointers in the vaxis cell buffer.

const std = @import("std");
const vaxis = @import("vaxis");
const state_mod = @import("state.zig");
const color_mod = @import("color.zig");
const masque_mod = @import("masque.zig");

/// Static digit strings for small numbers — avoids bufPrint for counts.
const digits = [_][]const u8{ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9" };

pub fn render(
    win: vaxis.Window,
    app: *const state_mod.AppState,
) void {
    // Header line — use multiple segments instead of bufPrint
    {
        const hdr_style: vaxis.Style = .{ .fg = .{ .rgb = .{ 200, 200, 200 } }, .bold = true };
        const segs = [_]vaxis.Segment{
            .{ .text = " Team: ", .style = hdr_style },
            .{ .text = app.teamName(), .style = hdr_style },
            .{ .text = "    Size: ", .style = hdr_style },
            .{ .text = if (app.team_count < digits.len) digits[app.team_count] else "?", .style = hdr_style },
            .{ .text = "/", .style = hdr_style },
            .{ .text = if (state_mod.max_team_size < digits.len) digits[state_mod.max_team_size] else "?", .style = hdr_style },
            .{ .text = "    Awareness: [", .style = hdr_style },
            .{ .text = if (app.awareness) "ON" else "OFF", .style = .{
                .fg = .{ .rgb = if (app.awareness) [3]u8{ 100, 255, 100 } else [3]u8{ 255, 100, 100 } },
                .bold = true,
            } },
            .{ .text = "]", .style = hdr_style },
        };
        _ = win.print(&segs, .{ .row_offset = 0, .col_offset = 0 });
    }

    // Team slots
    const slot_w: usize = @max(12, win.width / state_mod.max_team_size);
    for (0..state_mod.max_team_size) |i| {
        const slot_x = i * slot_w;
        const is_cursor = (app.focus == .roster and i == app.roster_cursor);

        if (i < app.team_count) {
            if (app.team[i]) |member| {
                renderFilledSlot(win, slot_x, member, is_cursor, slot_w);
            }
        } else {
            renderEmptySlot(win, slot_x, is_cursor, slot_w);
        }
    }

    // Synergy indicators — use separate print calls per pair
    {
        var synergy_col: u16 = 0;
        for (0..app.team_count) |ai| {
            if (app.team[ai]) |a| {
                if (masque_mod.findComplement(a.name)) |comp| {
                    for (0..app.team_count) |bi| {
                        if (app.team[bi]) |b| {
                            if (std.mem.eql(u8, b.name, comp) and std.mem.lessThan(u8, a.name, comp)) {
                                const syn_style: vaxis.Style = .{ .fg = .{ .rgb = .{ 255, 215, 0 } }, .italic = true };
                                const segs = [_]vaxis.Segment{
                                    .{ .text = " <> ", .style = syn_style },
                                    .{ .text = a.name, .style = syn_style },
                                    .{ .text = " + ", .style = syn_style },
                                    .{ .text = comp, .style = syn_style },
                                };
                                _ = win.print(&segs, .{ .row_offset = 3, .col_offset = synergy_col });
                                synergy_col +|= @intCast(4 + a.name.len + 3 + comp.len);
                            }
                        }
                    }
                }
            }
        }
    }

    // Help bar
    {
        const help = if (win.width >= 70)
            " [Enter] Add  [Bksp] Remove  [T] Tag  [A] Aware  [N] Name  [W] Write  [Q] Quit"
        else
            " Ent:Add Bk:Rm T:Tag A:Aw N:Name W:Write Q:Quit";

        const seg: vaxis.Segment = .{
            .text = help,
            .style = .{ .fg = .{ .rgb = .{ 100, 100, 100 } } },
        };
        const help_row: u16 = @intCast(if (win.height > 1) win.height - 1 else 0);
        _ = win.print(&.{seg}, .{ .row_offset = help_row, .col_offset = 0 });
    }
}

fn renderFilledSlot(
    win: vaxis.Window,
    slot_x: usize,
    member: state_mod.TeamMember,
    is_cursor: bool,
    slot_w: usize,
) void {
    const colors = color_mod.domainColors(member.domain);
    const border_color: [3]u8 = if (is_cursor) .{ 255, 255, 255 } else colors.primary;

    const slot = win.child(.{
        .x_off = @intCast(slot_x),
        .y_off = 1,
        .width = @intCast(slot_w),
        .height = @intCast(2),
        .border = .{
            .where = .all,
            .style = .{ .fg = .{ .rgb = border_color } },
            .glyphs = if (is_cursor) .{ .custom = .{ "┏", "━", "┓", "┃", "┛", "┗" } } else .single_rounded,
        },
    });

    // Fill slot background with domain tint
    {
        const slot_bg = color_mod.dimColor(colors.primary, if (is_cursor) 0.15 else 0.08);
        const slot_bg_color: vaxis.Color = .{ .rgb = slot_bg };
        for (0..slot.height) |sy| {
            for (0..slot.width) |sx| {
                slot.writeCell(@intCast(sx), @intCast(sy), .{
                    .char = .{ .grapheme = " ", .width = 1 },
                    .style = .{ .bg = slot_bg_color },
                });
            }
        }
    }

    const slot_name_bg = color_mod.dimColor(colors.primary, if (is_cursor) 0.15 else 0.08);
    const name_max = @min(member.name.len, slot.width);
    const name_seg: vaxis.Segment = .{
        .text = member.name[0..name_max],
        .style = .{ .fg = .{ .rgb = colors.bright }, .bg = .{ .rgb = slot_name_bg }, .bold = true },
    };
    _ = slot.print(&.{name_seg}, .{ .row_offset = 0, .col_offset = 0 });

    // Role — use separate icon + label segments instead of bufPrint
    if (member.role != .none) {
        const role_color: vaxis.Style = .{ .fg = .{ .rgb = .{ 255, 215, 0 } } };
        const segs = [_]vaxis.Segment{
            .{ .text = member.role.icon(), .style = role_color },
            .{ .text = " ", .style = role_color },
            .{ .text = member.role.label(), .style = role_color },
        };
        _ = slot.print(&segs, .{ .row_offset = 1, .col_offset = 0 });
    }
}

fn renderEmptySlot(
    win: vaxis.Window,
    slot_x: usize,
    is_cursor: bool,
    slot_w: usize,
) void {
    const border_color: [3]u8 = if (is_cursor) .{ 150, 150, 150 } else .{ 60, 60, 60 };

    const slot = win.child(.{
        .x_off = @intCast(slot_x),
        .y_off = 1,
        .width = @intCast(slot_w),
        .height = @intCast(2),
        .border = .{
            .where = .all,
            .style = .{ .fg = .{ .rgb = border_color } },
            .glyphs = .{ .custom = .{ "┌", "╌", "┐", "╎", "┘", "└" } },
        },
    });

    const seg: vaxis.Segment = .{
        .text = "empty",
        .style = .{ .fg = .{ .rgb = .{ 80, 80, 80 } } },
    };
    _ = slot.print(&.{seg}, .{ .row_offset = 0, .col_offset = 1 });
}
