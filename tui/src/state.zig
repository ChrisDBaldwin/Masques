/// Application state: cursor, team, tabs, focus, portraits.

const std = @import("std");
const masque_mod = @import("masque.zig");
const portrait_mod = @import("portrait.zig");

pub const Screen = enum { lobby, draft };
pub const Focus = enum { grid, roster, name_input };
pub const LobbyFocus = enum {
    menu,
    team_list,
    name_input,
    size_input,
    intent_input,
    masque_name_input,
    masque_domain_input,
    masque_who_input,
    masque_what_input,
    masque_how_input,
    masque_why_input,
};

pub const min_team_size: usize = 2;
pub const default_team_size: usize = 5;

pub const TeamEntryMember = struct {
    name: []const u8,
    role: []const u8,
    version: []const u8,
    brief: []const u8,
};

pub const TeamEntry = struct {
    name: []const u8,
    filename: []const u8,
    size: usize,
    members: []TeamEntryMember,
    intent: []const u8,
};

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
    version: []const u8,
};

pub const AppState = struct {
    // Screen
    screen: Screen = .lobby,

    // Data
    masques: []masque_mod.Masque = &.{},
    load_error: ?[]const u8 = null,

    // Portraits - one per masque
    portraits: []portrait_mod.Portrait = &.{},

    // Grid state
    grid_cursor: usize = 0,
    active_tab: masque_mod.Category = .all,
    grid_cols: usize = 3,

    // Roster state — dynamically allocated
    team: []?TeamMember = &.{},
    max_team_size: usize = default_team_size,
    team_count: usize = 0,
    roster_cursor: usize = 0,
    team_name_buf: [64]u8 = undefined,
    team_name_len: usize = 0,
    awareness: bool = true,

    // Lobby state
    lobby_entries: []TeamEntry = &.{},
    lobby_cursor: usize = 0,
    lobby_focus: LobbyFocus = .menu,
    menu_cursor: usize = 0,
    browse_mode: bool = false,

    // New Masque madlib buffers
    masque_name_buf: [64]u8 = undefined,
    masque_name_len: usize = 0,
    masque_domain_buf: [64]u8 = undefined,
    masque_domain_len: usize = 0,
    masque_who_buf: [256]u8 = undefined,
    masque_who_len: usize = 0,
    masque_what_buf: [256]u8 = undefined,
    masque_what_len: usize = 0,
    masque_how_buf: [256]u8 = undefined,
    masque_how_len: usize = 0,
    masque_why_buf: [256]u8 = undefined,
    masque_why_len: usize = 0,
    lobby_name_buf: [64]u8 = undefined,
    lobby_name_len: usize = 0,
    lobby_size_buf: [4]u8 = undefined,
    lobby_size_len: usize = 0,
    lobby_intent_buf: [512]u8 = undefined,
    lobby_intent_len: usize = 0,

    // Team intent (draft screen)
    intent_buf: [512]u8 = undefined,
    intent_len: usize = 0,

    // UI state
    focus: Focus = .grid,
    notification: ?[]const u8 = null,
    notification_tick: u32 = 0,
    current_tick: u32 = 0,

    // Text input for team name (draft screen)
    name_input_buf: [64]u8 = undefined,
    name_input_len: usize = 0,

    pub fn teamName(self: *const AppState) []const u8 {
        return self.team_name_buf[0..self.team_name_len];
    }

    pub fn teamIntent(self: *const AppState) []const u8 {
        return self.intent_buf[0..self.intent_len];
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
        return self.team[0..self.max_team_size];
    }

    /// Static digit strings for small numbers — avoids bufPrint for counts.
    pub const digits = [_][]const u8{ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "13", "14", "15", "16", "17", "18", "19", "20" };

    pub fn digitStr(n: usize) []const u8 {
        if (n < digits.len) return digits[n];
        return "?";
    }
};
