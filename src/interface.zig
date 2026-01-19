// Masque interface - core data structures and operations
// This is the runtime representation of a masque

const std = @import("std");

pub const Ring = enum {
    admin,
    player,
    guest,
    outsider,

    pub fn fromString(s: []const u8) Ring {
        if (std.mem.eql(u8, s, "admin")) return .admin;
        if (std.mem.eql(u8, s, "player")) return .player;
        if (std.mem.eql(u8, s, "guest")) return .guest;
        return .outsider;
    }

    pub fn toString(self: Ring) []const u8 {
        return switch (self) {
            .admin => "admin",
            .player => "player",
            .guest => "guest",
            .outsider => "outsider",
        };
    }

    pub fn level(self: Ring) u8 {
        return switch (self) {
            .admin => 3,
            .player => 2,
            .guest => 1,
            .outsider => 0,
        };
    }
};

pub const Masque = struct {
    // Identity
    name: []const u8,
    index: i64,
    version: []const u8,

    // Trust
    ring: Ring,

    // The five components
    context: []const u8,
    lens: []const u8,
    intent_allowed: []const []const u8,
    intent_denied: []const []const u8,
    knowledge: []const []const u8,

    // Access
    vault_role: []const u8,
    ttl: []const u8,

    // Attributes
    domain: []const u8,
    stack: []const u8,
    style: []const u8,
    philosophy: []const u8,
    tagline: []const u8,

    pub fn qualifyIntent(self: *const Masque, intent: []const u8) bool {
        const intent_mod = @import("intent.zig");
        return intent_mod.qualifyIntent(self.intent_allowed, self.intent_denied, intent);
    }
};

// Session represents an active masque session
pub const Session = struct {
    masque_name: []const u8,
    masque_version: []const u8,
    intent: []const u8,
    session_id: []const u8,
    started_at: i64,
    ring: Ring,

    pub fn isActive(self: *const Session) bool {
        return self.session_id.len > 0;
    }
};

// MasqueInfo is the JSON-serializable info response
pub const MasqueInfo = struct {
    name: []const u8,
    version: []const u8,
    ring: []const u8,
    index: i64,
    domain: []const u8,
    stack: []const u8,
    philosophy: []const u8,
    tagline: []const u8,
    intent_allowed: []const []const u8,
    intent_denied: []const []const u8,
    capabilities: []const []const u8,

    pub fn fromMasque(m: *const Masque) MasqueInfo {
        return .{
            .name = m.name,
            .version = m.version,
            .ring = m.ring.toString(),
            .index = m.index,
            .domain = m.domain,
            .stack = m.stack,
            .philosophy = m.philosophy,
            .tagline = m.tagline,
            .intent_allowed = m.intent_allowed,
            .intent_denied = m.intent_denied,
            .capabilities = &[_][]const u8{ "info", "qualify", "don", "doff", "announce", "discover", "message", "listen" },
        };
    }
};

test "ring levels" {
    try std.testing.expectEqual(@as(u8, 3), Ring.admin.level());
    try std.testing.expectEqual(@as(u8, 2), Ring.player.level());
    try std.testing.expectEqual(@as(u8, 1), Ring.guest.level());
    try std.testing.expectEqual(@as(u8, 0), Ring.outsider.level());
}

test "ring from string" {
    try std.testing.expectEqual(Ring.admin, Ring.fromString("admin"));
    try std.testing.expectEqual(Ring.player, Ring.fromString("player"));
    try std.testing.expectEqual(Ring.guest, Ring.fromString("guest"));
    try std.testing.expectEqual(Ring.outsider, Ring.fromString("outsider"));
    try std.testing.expectEqual(Ring.outsider, Ring.fromString("unknown"));
}
