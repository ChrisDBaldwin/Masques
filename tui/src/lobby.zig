/// Lobby screen — list saved teams, create new ones.

const std = @import("std");
const vaxis = @import("vaxis");
const state_mod = @import("state.zig");
const portrait_mod = @import("portrait.zig");
const Yaml = @import("yaml").Yaml;

/// Scan ~/.masques/ for *.team.yaml files, parse each, return entries.
pub fn loadTeamEntries(alloc: std.mem.Allocator) ![]state_mod.TeamEntry {
    const home = std.posix.getenv("MASQUES_HOME") orelse blk: {
        const h = std.posix.getenv("HOME") orelse return error.NoHomeDir;
        break :blk h;
    };

    var dir_buf: [512]u8 = undefined;
    const dir_path = if (std.posix.getenv("MASQUES_HOME") != null)
        try std.fmt.bufPrint(&dir_buf, "{s}", .{home})
    else
        try std.fmt.bufPrint(&dir_buf, "{s}/.masques", .{home});

    var dir = std.fs.cwd().openDir(dir_path, .{ .iterate = true }) catch {
        return try alloc.alloc(state_mod.TeamEntry, 0);
    };
    defer dir.close();

    // First pass: count team files
    var count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (std.mem.endsWith(u8, entry.name, ".team.yaml")) count += 1;
    }

    if (count == 0) return try alloc.alloc(state_mod.TeamEntry, 0);

    var entries = try alloc.alloc(state_mod.TeamEntry, count);
    var ei: usize = 0;

    // Second pass: parse each
    var iter2 = dir.iterate();
    while (try iter2.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".team.yaml")) continue;

        if (parseTeamFile(alloc, dir, entry.name)) |te| {
            entries[ei] = te;
            ei += 1;
        } else |_| {}
    }

    return entries[0..ei];
}

fn parseTeamFile(
    alloc: std.mem.Allocator,
    dir: std.fs.Dir,
    filename: []const u8,
) !state_mod.TeamEntry {
    const file = try dir.openFile(filename, .{});
    defer file.close();

    const source = try file.readToEndAlloc(alloc, 64 * 1024);
    defer alloc.free(source);

    var yaml: Yaml = .{ .source = source };
    defer yaml.deinit(alloc);

    yaml.load(alloc) catch return error.ParseFailure;

    if (yaml.docs.items.len == 0) return error.Empty;

    const doc = yaml.docs.items[0];
    const map = switch (doc) {
        .map => |m| m,
        else => return error.InvalidFormat,
    };

    const name_val = map.get("name") orelse return error.MissingName;
    const name = switch (name_val) {
        .scalar => |s| s,
        else => return error.InvalidFormat,
    };

    const size_val = map.get("size");
    const size: usize = if (size_val) |sv| blk: {
        const sv_str = switch (sv) {
            .scalar => |s| s,
            else => break :blk @as(usize, 0),
        };
        break :blk std.fmt.parseInt(usize, sv_str, 10) catch 0;
    } else 0;

    // Parse roster
    var members: []state_mod.TeamEntryMember = &.{};
    if (map.get("roster")) |roster_val| {
        const roster_list = switch (roster_val) {
            .list => |l| l,
            else => &.{},
        };
        if (roster_list.len > 0) {
            var mem_list = try alloc.alloc(state_mod.TeamEntryMember, roster_list.len);
            var mi: usize = 0;
            for (roster_list) |item| {
                const m = switch (item) {
                    .map => |m2| m2,
                    else => continue,
                };
                // Try "masque" key first (new format), fall back to "name" (legacy)
                const mname = if (m.get("masque")) |v| (switch (v) {
                    .scalar => |s| s,
                    else => "?",
                }) else if (m.get("name")) |v| (switch (v) {
                    .scalar => |s| s,
                    else => "?",
                }) else "?";
                const mrole = if (m.get("role")) |v| (switch (v) {
                    .scalar => |s| s,
                    else => "",
                }) else "";
                const mversion = if (m.get("version")) |v| (switch (v) {
                    .scalar => |s| s,
                    else => "",
                }) else "";
                const mbrief = if (m.get("brief")) |v| (switch (v) {
                    .scalar => |s| s,
                    else => "",
                }) else "";

                mem_list[mi] = .{
                    .name = try alloc.dupe(u8, mname),
                    .role = try alloc.dupe(u8, mrole),
                    .version = try alloc.dupe(u8, mversion),
                    .brief = try alloc.dupe(u8, mbrief),
                };
                mi += 1;
            }
            members = mem_list[0..mi];
        }
    }

    // Parse intent field
    const intent_val = map.get("intent");
    const intent = if (intent_val) |iv| switch (iv) {
        .scalar => |s| s,
        else => "",
    } else "";

    return .{
        .name = try alloc.dupe(u8, name),
        .filename = try alloc.dupe(u8, filename),
        .size = if (size > 0) size else members.len,
        .members = members,
        .intent = try alloc.dupe(u8, std.mem.trim(u8, intent, " \n\t\r")),
    };
}

pub fn deinitTeamEntries(alloc: std.mem.Allocator, entries: []state_mod.TeamEntry) void {
    for (entries) |e| {
        alloc.free(e.name);
        alloc.free(e.filename);
        if (e.intent.len > 0) alloc.free(e.intent);
        for (e.members) |m| {
            alloc.free(m.name);
            alloc.free(m.role);
            if (m.version.len > 0) alloc.free(m.version);
            if (m.brief.len > 0) alloc.free(m.brief);
        }
        if (e.members.len > 0) alloc.free(e.members);
    }
    if (entries.len > 0) alloc.free(entries);
}

// ─── Rendering ───────────────────────────────────────────────────────

pub fn render(win: vaxis.Window, app: *state_mod.AppState) void {
    // Gradient title: M A S Q U E S   L O B B Y
    {
        const title = "M A S Q U E S   L O B B Y";
        const x: u16 = if (win.width > title.len) @intCast((win.width - title.len) / 2) else 0;

        const char_table = comptime blk: {
            var t: [128][1]u8 = undefined;
            for (0..128) |i| {
                t[i] = .{@intCast(i)};
            }
            break :blk t;
        };

        for (title, 0..) |ch, i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(@max(1, title.len - 1)));
            const r: u8 = 255;
            const g: u8 = @intFromFloat(107.0 + (215.0 - 107.0) * t);
            const b: u8 = @intFromFloat(107.0 * (1.0 - t));
            const bg_r: u8 = @intFromFloat(40.0 * (1.0 - t) + 30.0 * t);
            const bg_g: u8 = @intFromFloat(15.0 * (1.0 - t) + 30.0 * t);
            const bg_b: u8 = @intFromFloat(15.0 * (1.0 - t) + 5.0 * t);
            const col_x: u16 = x +| @as(u16, @intCast(i));
            if (col_x < win.width) {
                const idx: usize = if (ch < 128) ch else ' ';
                win.writeCell(col_x, 0, .{
                    .char = .{ .grapheme = &char_table[idx], .width = 1 },
                    .style = .{
                        .fg = .{ .rgb = .{ r, g, b } },
                        .bg = .{ .rgb = .{ bg_r, bg_g, bg_b } },
                        .bold = true,
                    },
                });
            }
        }
    }

    // Subtitle
    {
        const sub = "Select a team or create a new one";
        const sx: u16 = if (win.width > sub.len) @intCast((win.width - sub.len) / 2) else 0;
        const seg: vaxis.Segment = .{
            .text = sub,
            .style = .{ .fg = .{ .rgb = .{ 120, 120, 120 } } },
        };
        _ = win.print(&.{seg}, .{ .row_offset = 2, .col_offset = sx });
    }

    const list_start_row: u16 = 4;

    // Determine portrait panel dimensions
    const show_portraits = win.width > 60 and app.lobby_entries.len > 0;
    const portrait_panel_w: u16 = if (show_portraits) 20 else 0;

    if (app.lobby_entries.len == 0) {
        // Empty state
        const empty = "No saved teams \u{2014} press [N] to create one";
        const ex: u16 = if (win.width > empty.len) @intCast((win.width - empty.len) / 2) else 0;
        const seg: vaxis.Segment = .{
            .text = empty,
            .style = .{ .fg = .{ .rgb = .{ 100, 100, 100 } }, .italic = true },
        };
        _ = win.print(&.{seg}, .{ .row_offset = list_start_row + 2, .col_offset = ex });
    } else {
        // Team list (constrained to avoid portrait panel overlap)
        const list_max_w: u16 = if (portrait_panel_w > 0) win.width -| (portrait_panel_w + 2) else win.width;
        _ = list_max_w;

        for (app.lobby_entries, 0..) |entry, i| {
            const row: u16 = list_start_row + @as(u16, @intCast(i * 2));
            if (row >= win.height -| 3) break;

            const is_cursor = (app.lobby_focus == .list and i == app.lobby_cursor);

            // Cursor indicator
            const indicator: vaxis.Segment = .{
                .text = if (is_cursor) " > " else "   ",
                .style = .{ .fg = .{ .rgb = .{ 255, 215, 0 } }, .bold = true },
            };

            // Team name
            const name_seg: vaxis.Segment = .{
                .text = entry.name,
                .style = .{
                    .fg = .{ .rgb = if (is_cursor) [3]u8{ 255, 255, 255 } else [3]u8{ 200, 200, 200 } },
                    .bold = is_cursor,
                },
            };

            // Size
            const size_str = state_mod.AppState.digitStr(entry.size);
            const size_seg: vaxis.Segment = .{
                .text = size_str,
                .style = .{ .fg = .{ .rgb = .{ 150, 150, 150 } } },
            };

            const paren_l: vaxis.Segment = .{ .text = "  (", .style = .{ .fg = .{ .rgb = .{ 100, 100, 100 } } } };
            const paren_m: vaxis.Segment = .{ .text = " members)", .style = .{ .fg = .{ .rgb = .{ 100, 100, 100 } } } };

            _ = win.print(&.{ indicator, name_seg, paren_l, size_seg, paren_m }, .{ .row_offset = row, .col_offset = 1 });

            // Member names on next line
            if (entry.members.len > 0) {
                const indent: vaxis.Segment = .{ .text = "     ", .style = .{} };
                // Build a comma-separated display using segments
                var segs: [21]vaxis.Segment = undefined; // max 10 members with commas + indent
                segs[0] = indent;
                var si: usize = 1;
                for (entry.members, 0..) |member, mi| {
                    if (mi > 0 and si < segs.len) {
                        segs[si] = .{ .text = ", ", .style = .{ .fg = .{ .rgb = .{ 80, 80, 80 } } } };
                        si += 1;
                    }
                    if (si >= segs.len) break;
                    segs[si] = .{
                        .text = member.name,
                        .style = .{ .fg = .{ .rgb = .{ 140, 140, 140 } }, .italic = true },
                    };
                    si += 1;
                }
                _ = win.print(segs[0..si], .{ .row_offset = row + 1, .col_offset = 1 });
            }
        }
    }

    // Portrait strip for selected team's roster
    if (show_portraits and app.lobby_cursor < app.lobby_entries.len) {
        const entry = app.lobby_entries[app.lobby_cursor];
        if (entry.members.len > 0) {
            const portrait_x: u16 = win.width -| portrait_panel_w;
            const thumb_h: u16 = @intCast(portrait_mod.thumb_h);
            const thumb_w: u16 = @intCast(portrait_mod.thumb_w);
            const slot_h: u16 = thumb_h + 2; // portrait + name + gap
            const max_portraits: usize = @intCast((win.height -| (list_start_row + 2)) / slot_h);
            const show_count = @min(entry.members.len, @min(max_portraits, 4));

            for (entry.members[0..show_count], 0..) |member, pi| {
                const py: u16 = list_start_row + @as(u16, @intCast(pi)) * slot_h;
                if (py + thumb_h >= win.height -| 2) break;

                // Look up masque index for this member
                var found_idx: ?usize = null;
                for (app.masques, 0..) |m, mi| {
                    if (std.mem.eql(u8, m.name, member.name)) {
                        found_idx = mi;
                        break;
                    }
                }

                if (found_idx) |idx| {
                    if (idx < app.portraits.len) {
                        const portrait_win = win.child(.{
                            .x_off = portrait_x + 3,
                            .y_off = py,
                            .width = thumb_w,
                            .height = thumb_h,
                        });
                        app.portraits[idx].render(portrait_win);
                    }
                }

                // Member name below portrait
                const name_x: u16 = portrait_x + 3;
                const name_seg: vaxis.Segment = .{
                    .text = member.name,
                    .style = .{ .fg = .{ .rgb = .{ 160, 160, 160 } }, .italic = true },
                };
                _ = win.print(&.{name_seg}, .{ .row_offset = py + thumb_h, .col_offset = name_x });
            }
        }
    }

    // Help bar
    {
        const help = " [Enter] Load  [N] New Team  [Q] Quit";
        const seg: vaxis.Segment = .{
            .text = help,
            .style = .{ .fg = .{ .rgb = .{ 100, 100, 100 } } },
        };
        const help_row: u16 = @intCast(if (win.height > 1) win.height - 1 else 0);
        _ = win.print(&.{seg}, .{ .row_offset = help_row, .col_offset = 0 });
    }

    // Notification overlay
    if (app.notification) |notif| {
        const notif_style: vaxis.Style = .{
            .fg = .{ .rgb = .{ 255, 215, 0 } },
            .bold = true,
        };
        const seg: vaxis.Segment = .{ .text = notif, .style = notif_style };
        const notif_row: u16 = @intCast(if (win.height > 2) win.height - 2 else 0);
        _ = win.print(&.{seg}, .{ .row_offset = notif_row, .col_offset = 2 });
    }

    // Name input overlay
    if (app.lobby_focus == .name_input) {
        renderInputOverlay(win, "Team Name:", app.lobby_name_buf[0..app.lobby_name_len]);
    }

    // Size input overlay
    if (app.lobby_focus == .size_input) {
        renderInputOverlay(win, "Team Size (min 2):", app.lobby_size_buf[0..app.lobby_size_len]);
    }

    // Intent input overlay
    if (app.lobby_focus == .intent_input) {
        renderInputOverlay(win, "Team Intent:", app.lobby_intent_buf[0..app.lobby_intent_len]);
    }
}

fn renderInputOverlay(win: vaxis.Window, label: []const u8, input_text: []const u8) void {
    const overlay_w: u16 = 40;
    const overlay_x: u16 = if (win.width > overlay_w) @intCast((win.width - overlay_w) / 2) else 0;
    const overlay_y: u16 = @intCast(win.height / 3);

    const overlay = win.child(.{
        .x_off = overlay_x,
        .y_off = overlay_y,
        .width = overlay_w,
        .height = 5,
        .border = .{
            .where = .all,
            .style = .{ .fg = .{ .rgb = .{ 255, 215, 0 } } },
            .glyphs = .single_rounded,
        },
    });

    // Clear overlay background
    for (0..overlay.height) |y| {
        for (0..overlay.width) |x| {
            overlay.writeCell(@intCast(x), @intCast(y), .{
                .char = .{ .grapheme = " ", .width = 1 },
                .style = .{ .bg = .{ .rgb = .{ 20, 20, 20 } } },
            });
        }
    }

    const label_seg: vaxis.Segment = .{
        .text = label,
        .style = .{ .fg = .{ .rgb = .{ 200, 200, 200 } }, .bg = .{ .rgb = .{ 20, 20, 20 } }, .bold = true },
    };
    _ = overlay.print(&.{label_seg}, .{ .row_offset = 0, .col_offset = 1 });

    const input_seg: vaxis.Segment = .{
        .text = input_text,
        .style = .{ .fg = .{ .rgb = .{ 255, 255, 255 } }, .bg = .{ .rgb = .{ 20, 20, 20 } } },
    };
    const cursor_seg: vaxis.Segment = .{
        .text = "_",
        .style = .{ .fg = .{ .rgb = .{ 255, 215, 0 } }, .bg = .{ .rgb = .{ 20, 20, 20 } }, .bold = true },
    };
    _ = overlay.print(&.{ input_seg, cursor_seg }, .{ .row_offset = 2, .col_offset = 1 });
}
