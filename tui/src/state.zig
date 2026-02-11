/// Application state: cursor, team, tabs, focus, portraits.

const std = @import("std");
const masque_mod = @import("masque.zig");
const portrait_mod = @import("portrait.zig");

pub const Focus = enum { grid, roster, name_input };

pub const max_team_size: usize = 5;
pub const min_team_size: usize = 2;

pub const Role = enum {
    none,
    point,
    coach,

    pub fn label(self: Role) []const u8 {
        return switch (self) {
            .none => "",
            .point => "POINT",
            .coach => "COACH",
        };
    }

    pub fn icon(self: Role) []const u8 {
        return switch (self) {
            .none => " ",
            .point => ">",
            .coach => "~",
        };
    }

    pub fn next(self: Role) Role {
        return switch (self) {
            .none => .point,
            .point => .coach,
            .coach => .none,
        };
    }
};

pub const TeamMember = struct {
    name: []const u8,
    domain: []const u8,
    role: Role,
};

pub const AppState = struct {
    // Data
    masques: []masque_mod.Masque = &.{},
    personas_dir: []const u8 = "",
    load_error: ?[]const u8 = null,

    // Portraits - one per masque
    portraits: []portrait_mod.Portrait = &.{},

    // Grid state
    grid_cursor: usize = 0,
    active_tab: masque_mod.Category = .all,
    grid_cols: usize = 3,

    // Roster state
    team: [max_team_size]?TeamMember = .{ null, null, null, null, null },
    team_count: usize = 0,
    roster_cursor: usize = 0,
    team_name_buf: [64]u8 = undefined,
    team_name_len: usize = 0,
    awareness: bool = true,

    // UI state
    focus: Focus = .grid,
    notification: ?[]const u8 = null,
    notification_tick: u32 = 0,
    current_tick: u32 = 0,

    // Text input for team name
    name_input_buf: [64]u8 = undefined,
    name_input_len: usize = 0,

    pub fn teamName(self: *const AppState) []const u8 {
        return self.team_name_buf[0..self.team_name_len];
    }

    pub fn setDefaultName(self: *AppState) void {
        const default_name = "Alpha Squad";
        @memcpy(self.team_name_buf[0..default_name.len], default_name);
        self.team_name_len = default_name.len;
    }

    /// Get the masque index that the grid cursor points to
    pub fn cursorMasqueIndex(self: *const AppState) ?usize {
        var vi: usize = 0;
        for (self.masques, 0..) |m, i| {
            if (self.active_tab == .all or m.category == self.active_tab) {
                if (vi == self.grid_cursor) return i;
                vi += 1;
            }
        }
        return null;
    }

    /// Count visible masques in current tab
    pub fn visibleCount(self: *const AppState) usize {
        if (self.active_tab == .all) return self.masques.len;
        var count: usize = 0;
        for (self.masques) |m| {
            if (m.category == self.active_tab) count += 1;
        }
        return count;
    }

    pub fn setNotification(self: *AppState, msg: []const u8) void {
        self.notification = msg;
        self.notification_tick = self.current_tick + 90; // ~3 seconds at 30fps
    }

    pub fn teamSlice(self: *const AppState) []const ?TeamMember {
        return self.team[0..max_team_size];
    }

    pub fn teamMembers(self: *const AppState) [max_team_size]?TeamMember {
        return self.team;
    }
};
