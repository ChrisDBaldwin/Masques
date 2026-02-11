const std = @import("std");
const vaxis = @import("vaxis");
const masque_mod = @import("masque.zig");
const portrait_mod = @import("portrait.zig");
const state_mod = @import("state.zig");
const layout_mod = @import("layout.zig");
const grid_mod = @import("grid.zig");
const detail_mod = @import("detail.zig");
const roster_mod = @import("roster.zig");
const writer_mod = @import("writer.zig");

pub const std_options: std.Options = .{
    .log_level = .warn,
};

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
    tick,
};

var running: bool = true;

fn timerThread(loop: *vaxis.Loop(Event)) void {
    while (running) {
        std.Thread.sleep(33 * std.time.ns_per_ms); // ~30fps
        if (!running) break;
        loop.postEvent(.tick);
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var buffer: [4096]u8 = undefined;
    var tty = try vaxis.Tty.init(&buffer);
    defer tty.deinit();

    var vx = try vaxis.init(alloc, .{});
    defer vx.deinit(alloc, tty.writer());

    var loop: vaxis.Loop(Event) = .{
        .tty = &tty,
        .vaxis = &vx,
    };
    try loop.init();
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    // Use semicolon-delimited SGR (universally supported).
    // The colon-delimited "standard" format is not supported by
    // Terminal.app, older iTerm2, or many other common terminals.
    vx.sgr = .legacy;

    // Start animation timer thread
    const timer_thread = try std.Thread.spawn(.{}, timerThread, .{&loop});

    defer {
        running = false;
        timer_thread.join();
    }

    // Initialize app state
    var app = state_mod.AppState{};
    app.setDefaultName();

    // Load masques
    const paths_to_try = [_][]const u8{
        "personas/manifest.yaml",
        "../personas/manifest.yaml",
    };
    for (paths_to_try) |path| {
        if (masque_mod.loadManifest(alloc, path)) |masques| {
            app.masques = masques;
            if (std.mem.lastIndexOf(u8, path, "/")) |idx| {
                app.personas_dir = path[0..idx];
            }
            break;
        } else |_| {}
    }

    if (app.masques.len == 0) {
        app.load_error = "Could not load personas/manifest.yaml";
    }

    // Initialize portraits for each masque
    if (app.masques.len > 0) {
        var portraits = try alloc.alloc(portrait_mod.Portrait, app.masques.len);
        for (app.masques, 0..) |m, i| {
            portraits[i] = portrait_mod.Portrait.init(m.name, m.domain);
        }
        app.portraits = portraits;
    }

    // Cleanup masques and portraits on exit
    defer {
        if (app.masques.len > 0) masque_mod.deinitMasques(alloc, app.masques);
        if (app.portraits.len > 0) alloc.free(app.portraits);
    }

    // Main event loop
    while (true) {
        const event = loop.nextEvent();
        switch (event) {
            .key_press => |key| {
                if (app.focus == .name_input) {
                    if (handleNameInput(&app, key)) break;
                } else {
                    if (handleKey(&app, key, alloc)) break;
                }
            },
            .winsize => |ws| try vx.resize(alloc, tty.writer(), ws),
            .tick => {
                app.current_tick +%= 1;

                // Clear notification if expired
                if (app.notification != null and app.current_tick > app.notification_tick) {
                    app.notification = null;
                }

                // Update portrait animations
                updatePortraits(&app);
            },
            .focus_in => {},
        }

        // Render
        const win = vx.window();
        win.clear();

        if (app.load_error) |err| {
            const seg: vaxis.Segment = .{
                .text = err,
                .style = .{ .fg = .{ .rgb = .{ 255, 80, 80 } } },
            };
            _ = win.print(&.{seg}, .{ .row_offset = 1, .col_offset = 1 });
            const seg2: vaxis.Segment = .{
                .text = "Run from the masques repo root. Press q to quit.",
                .style = .{ .fg = .{ .rgb = .{ 150, 150, 150 } } },
            };
            _ = win.print(&.{seg2}, .{ .row_offset = 3, .col_offset = 1 });
        } else {
            renderApp(win, &app);
        }

        try vx.render(tty.writer());
    }
}

fn handleKey(app: *state_mod.AppState, key: vaxis.Key, alloc: std.mem.Allocator) bool {
    if (key.matches('q', .{}) or key.matches('c', .{ .ctrl = true })) return true;

    if (key.matches('1', .{})) { app.active_tab = .all; app.grid_cursor = 0; }
    if (key.matches('2', .{})) { app.active_tab = .executive; app.grid_cursor = 0; }
    if (key.matches('3', .{})) { app.active_tab = .cognitive; app.grid_cursor = 0; }
    if (key.matches('4', .{})) { app.active_tab = .specialist; app.grid_cursor = 0; }
    if (key.matches('5', .{})) { app.active_tab = .art; app.grid_cursor = 0; }
    if (key.matches('6', .{})) { app.active_tab = .meta; app.grid_cursor = 0; }

    if (key.matches('a', .{}) or key.matches('A', .{})) app.awareness = !app.awareness;
    if (key.matches('t', .{}) or key.matches('T', .{})) cycleRole(app);
    if (key.matches('n', .{}) or key.matches('N', .{})) {
        app.focus = .name_input;
        app.name_input_len = 0;
    }
    if (key.matches('w', .{}) or key.matches('W', .{})) writeTeam(app);

    if (key.matches(vaxis.Key.enter, .{})) {
        if (app.focus == .grid) addToTeam(app, alloc);
    }
    if (key.matches(vaxis.Key.backspace, .{})) removeFromTeam(app);
    if (key.matches(vaxis.Key.tab, .{})) {
        app.focus = if (app.focus == .grid) .roster else .grid;
    }
    if (key.matches(vaxis.Key.escape, .{})) {
        if (app.focus != .grid) {
            app.focus = .grid;
        } else {
            return true;
        }
    }

    // Arrow keys
    if (key.matches(vaxis.Key.up, .{})) {
        if (app.focus == .grid and app.grid_cursor >= app.grid_cols) {
            app.grid_cursor -= app.grid_cols;
        }
    }
    if (key.matches(vaxis.Key.down, .{})) {
        if (app.focus == .grid and app.grid_cursor + app.grid_cols < app.visibleCount()) {
            app.grid_cursor += app.grid_cols;
        }
    }
    if (key.matches(vaxis.Key.left, .{})) {
        if (app.focus == .grid) {
            app.grid_cursor -|= 1;
        } else if (app.focus == .roster) {
            app.roster_cursor -|= 1;
        }
    }
    if (key.matches(vaxis.Key.right, .{})) {
        if (app.focus == .grid) {
            if (app.grid_cursor + 1 < app.visibleCount()) app.grid_cursor += 1;
        } else if (app.focus == .roster) {
            if (app.roster_cursor + 1 < state_mod.max_team_size) app.roster_cursor += 1;
        }
    }

    // Eagerly load detail for cursor masque
    if (app.cursorMasqueIndex()) |idx| {
        if (!app.masques[idx].detail_loaded) {
            masque_mod.loadDetail(alloc, &app.masques[idx], app.personas_dir) catch {};
        }
    }

    return false;
}

fn handleNameInput(app: *state_mod.AppState, key: vaxis.Key) bool {
    if (key.matches(vaxis.Key.enter, .{})) {
        // Accept name
        if (app.name_input_len > 0) {
            @memcpy(app.team_name_buf[0..app.name_input_len], app.name_input_buf[0..app.name_input_len]);
            app.team_name_len = app.name_input_len;
        }
        app.focus = .grid;
    } else if (key.matches(vaxis.Key.escape, .{})) {
        app.focus = .grid;
    } else if (key.matches(vaxis.Key.backspace, .{})) {
        app.name_input_len -|= 1;
    } else {
        // Try to get the codepoint
        const cp = key.codepoint;
        if (cp >= 32 and cp < 127 and app.name_input_len < 63) {
            app.name_input_buf[app.name_input_len] = @intCast(cp);
            app.name_input_len += 1;
        }
    }
    return false;
}

fn addToTeam(app: *state_mod.AppState, alloc: std.mem.Allocator) void {
    if (app.team_count >= state_mod.max_team_size) {
        app.setNotification("Team is full (max 5)");
        return;
    }

    const masque_idx = app.cursorMasqueIndex() orelse return;
    const m = &app.masques[masque_idx];

    for (app.team[0..app.team_count]) |slot| {
        if (slot) |member| {
            if (std.mem.eql(u8, member.name, m.name)) {
                app.setNotification("Already on team");
                return;
            }
        }
    }

    masque_mod.loadDetail(alloc, m, app.personas_dir) catch {};

    app.team[app.team_count] = .{
        .name = m.name,
        .domain = m.domain,
        .role = .none,
    };
    app.team_count += 1;

    // Trigger confirm animation on the portrait
    if (masque_idx < app.portraits.len) {
        app.portraits[masque_idx].setState(.confirming);
    }

    app.setNotification("Added to team");
}

fn removeFromTeam(app: *state_mod.AppState) void {
    if (app.team_count == 0) return;

    const remove_idx = if (app.focus == .roster and app.roster_cursor < app.team_count)
        app.roster_cursor
    else
        app.team_count - 1;

    // Deselect the portrait
    for (app.masques, 0..) |m, i| {
        if (app.team[remove_idx]) |member| {
            if (std.mem.eql(u8, m.name, member.name) and i < app.portraits.len) {
                app.portraits[i].setState(.deselecting);
            }
        }
    }

    var idx: usize = remove_idx;
    while (idx + 1 < app.team_count) : (idx += 1) {
        app.team[idx] = app.team[idx + 1];
    }
    app.team[app.team_count - 1] = null;
    app.team_count -= 1;

    if (app.roster_cursor > 0 and app.roster_cursor >= app.team_count) {
        app.roster_cursor = if (app.team_count > 0) app.team_count - 1 else 0;
    }
}

fn cycleRole(app: *state_mod.AppState) void {
    if (app.team_count == 0) return;
    const idx = if (app.focus == .roster and app.roster_cursor < app.team_count)
        app.roster_cursor
    else if (app.team_count > 0)
        app.team_count - 1
    else
        return;

    if (app.team[idx]) |*member| {
        member.role = member.role.next();
    }
}

fn writeTeam(app: *state_mod.AppState) void {
    if (app.team_count < state_mod.min_team_size) {
        app.setNotification("Need at least 2 members");
        return;
    }
    if (writer_mod.writeTeamYaml(app)) |path| {
        _ = path;
        app.setNotification("Team file written!");
    } else |_| {
        app.setNotification("Error writing file");
    }
}

fn updatePortraits(app: *state_mod.AppState) void {
    const cursor_idx = app.cursorMasqueIndex();

    for (0..app.portraits.len) |i| {
        // Set portrait state based on selection
        const is_cursor = if (cursor_idx) |ci| ci == i else false;
        const is_on_team = isOnTeamByIndex(app, i);

        if (app.portraits[i].state != .confirming) {
            if (is_cursor) {
                if (app.portraits[i].state != .selected and app.portraits[i].state != .selecting) {
                    app.portraits[i].setState(.selecting);
                }
            } else if (is_on_team) {
                if (app.portraits[i].state != .selected) {
                    app.portraits[i].setState(.selected);
                }
            } else {
                if (app.portraits[i].state == .selected or app.portraits[i].state == .selecting) {
                    app.portraits[i].setState(.deselecting);
                }
            }
        }

        // Only animate at full rate for selected/nearby, slower for distant
        const should_tick = is_cursor or is_on_team or (app.current_tick % 4 == 0);
        if (should_tick) {
            app.portraits[i].update();
        }
    }
}

fn isOnTeamByIndex(app: *const state_mod.AppState, masque_idx: usize) bool {
    if (masque_idx >= app.masques.len) return false;
    const name = app.masques[masque_idx].name;
    for (app.team[0..app.team_count]) |slot| {
        if (slot) |member| {
            if (std.mem.eql(u8, member.name, name)) return true;
        }
    }
    return false;
}

fn renderApp(win: vaxis.Window, app: *state_mod.AppState) void {
    const lo = layout_mod.compute(win.width, win.height);

    // Sync layout-derived values back to app state for key handling
    app.grid_cols = lo.grid_cols;

    // Title — gradient from warm coral to gold
    {
        const title = "M A S Q U E   D R A F T";
        const x: u16 = if (win.width > title.len) @intCast((win.width - title.len) / 2) else 0;

        // Lookup table: ASCII byte → single-char slice
        const char_table = comptime blk: {
            var t: [128][1]u8 = undefined;
            for (0..128) |i| {
                t[i] = .{@intCast(i)};
            }
            break :blk t;
        };

        // Write character by character with interpolated color
        for (title, 0..) |ch, i| {
            const t: f32 = @as(f32, @floatFromInt(i)) / @as(f32, @floatFromInt(@max(1, title.len - 1)));
            // Coral (255, 107, 107) → Gold (255, 215, 0)
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

    // Tab bar
    {
        renderTabs(win, app, &lo);
    }

    // Grid panel (left)
    {
        const grid_win = win.child(.{
            .x_off = @intCast(lo.grid_x),
            .y_off = @intCast(lo.grid_y),
            .width = @intCast(lo.grid_w),
            .height = @intCast(lo.grid_h),
        });
        grid_mod.render(grid_win, app, &lo);
    }

    // Detail panel (right)
    {
        const color_mod = @import("color.zig");
        const detail_border_color: [3]u8 = if (app.cursorMasqueIndex()) |idx|
            color_mod.domainColors(app.masques[idx].domain).dim
        else
            .{ 60, 60, 60 };
        const detail_win = win.child(.{
            .x_off = @intCast(lo.detail_x),
            .y_off = @intCast(lo.detail_y),
            .width = @intCast(lo.detail_w),
            .height = @intCast(lo.detail_h),
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .rgb = detail_border_color } },
                .glyphs = .single_rounded,
            },
        });
        detail_mod.render(detail_win, app, &lo);
    }

    // Roster (bottom)
    {
        const roster_win = win.child(.{
            .x_off = 0,
            .y_off = @intCast(lo.roster_y),
            .width = @intCast(lo.roster_w),
            .height = @intCast(lo.roster_h),
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .rgb = .{ 60, 60, 60 } } },
                .glyphs = .single_rounded,
            },
        });
        roster_mod.render(roster_win, app);
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
    if (app.focus == .name_input) {
        const overlay_x: u16 = if (win.width > 40) @intCast((win.width - 40) / 2) else 0;
        const overlay_y: u16 = @intCast(win.height / 3);

        const overlay = win.child(.{
            .x_off = @intCast(overlay_x),
            .y_off = @intCast(overlay_y),
            .width = @intCast(40),
            .height = @intCast(5),
            .border = .{
                .where = .all,
                .style = .{ .fg = .{ .rgb = .{ 255, 215, 0 } } },
                .glyphs = .single_rounded,
            },
        });

        const label_seg: vaxis.Segment = .{
            .text = "Team Name:",
            .style = .{ .fg = .{ .rgb = .{ 200, 200, 200 } }, .bold = true },
        };
        _ = overlay.print(&.{label_seg}, .{ .row_offset = 0, .col_offset = 1 });

        const input_text = app.name_input_buf[0..app.name_input_len];
        const input_seg: vaxis.Segment = .{
            .text = input_text,
            .style = .{ .fg = .{ .rgb = .{ 255, 255, 255 } } },
        };
        const cursor_seg: vaxis.Segment = .{
            .text = "_",
            .style = .{ .fg = .{ .rgb = .{ 255, 215, 0 } }, .bold = true },
        };
        _ = overlay.print(&.{ input_seg, cursor_seg }, .{ .row_offset = 2, .col_offset = 1 });
    }
}

fn renderTabs(win: vaxis.Window, app: *const state_mod.AppState, lo: *const layout_mod.Layout) void {
    _ = lo;
    const color_mod = @import("color.zig");
    // Static string literals — no stack-local buffers, no dangling pointers
    const labels = [_][]const u8{
        " [1] All ",
        " [2] Executive ",
        " [3] Cognitive ",
        " [4] Specialist ",
        " [5] Art ",
        " [6] Meta ",
    };
    const categories = [_]masque_mod.Category{ .all, .executive, .cognitive, .specialist, .art, .meta };
    const tab_colors = [_][3]u8{
        .{ 200, 200, 200 }, // all - white
        .{ 100, 149, 237 }, // executive - cornflower
        .{ 0, 206, 209 },   // cognitive - turquoise
        .{ 205, 133, 63 },  // specialist - amber
        .{ 255, 111, 97 },  // art - coral
        .{ 180, 130, 255 }, // meta - lavender
    };

    var col_off: u16 = 1;
    for (categories, 0..) |cat, i| {
        const is_active = (cat == app.active_tab);
        const color = tab_colors[i];

        const style: vaxis.Style = if (is_active) .{
            .fg = .{ .rgb = .{ 255, 255, 255 } },
            .bg = .{ .rgb = color },
            .bold = true,
        } else .{
            .fg = .{ .rgb = color },
            .bg = .{ .rgb = color_mod.dimColor(color, 0.1) },
        };

        const seg: vaxis.Segment = .{ .text = labels[i], .style = style };
        _ = win.print(&.{seg}, .{ .row_offset = 1, .col_offset = col_off });
        col_off +|= @intCast(labels[i].len);
    }
}
