// Session management for masque binaries
// Tracks active sessions in ~/.masques/sessions/

const std = @import("std");

pub const Session = struct {
    id: []const u8,
    masque_name: []const u8,
    masque_version: []const u8,
    intent: []const u8,
    started_at: i64,
    ring: []const u8,

    pub fn deinit(self: *Session, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.masque_name);
        allocator.free(self.masque_version);
        allocator.free(self.intent);
        allocator.free(self.ring);
    }
};

pub const SessionManager = struct {
    allocator: std.mem.Allocator,
    sessions_dir: []const u8,

    pub fn init(allocator: std.mem.Allocator) !SessionManager {
        // Get home directory
        const home = std.process.getEnvVarOwned(allocator, "HOME") catch {
            return error.NoHomeDir;
        };
        defer allocator.free(home);

        const sessions_dir = try std.fmt.allocPrint(allocator, "{s}/.masques/sessions", .{home});

        // Ensure directory exists
        std.fs.cwd().makePath(sessions_dir) catch |err| {
            if (err != error.PathAlreadyExists) {
                allocator.free(sessions_dir);
                return err;
            }
        };

        return .{
            .allocator = allocator,
            .sessions_dir = sessions_dir,
        };
    }

    pub fn deinit(self: *SessionManager) void {
        self.allocator.free(self.sessions_dir);
    }

    pub fn createSession(
        self: *SessionManager,
        masque_name: []const u8,
        masque_version: []const u8,
        intent: []const u8,
        ring: []const u8,
    ) !Session {
        // Generate session ID
        const timestamp = std.time.timestamp();
        var random_bytes: [8]u8 = undefined;
        std.crypto.random.bytes(&random_bytes);

        // Format session ID: masque-timestamp-random
        var hex_buf: [16]u8 = undefined;
        _ = std.fmt.bufPrint(&hex_buf, "{x:0>16}", .{std.mem.readInt(u64, random_bytes[0..8], .big)}) catch unreachable;
        const session_id = try std.fmt.allocPrint(
            self.allocator,
            "{s}-{d}-{s}",
            .{ masque_name, timestamp, hex_buf[0..16] },
        );

        const session = Session{
            .id = session_id,
            .masque_name = try self.allocator.dupe(u8, masque_name),
            .masque_version = try self.allocator.dupe(u8, masque_version),
            .intent = try self.allocator.dupe(u8, intent),
            .started_at = timestamp,
            .ring = try self.allocator.dupe(u8, ring),
        };

        // Write session file
        try self.writeSessionFile(&session);

        return session;
    }

    pub fn endSession(self: *SessionManager, session_id: []const u8) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.sessions_dir, session_id });
        defer self.allocator.free(path);

        std.fs.cwd().deleteFile(path) catch |err| {
            if (err != error.FileNotFound) return err;
        };
    }

    pub fn getActiveSession(self: *SessionManager, masque_name: []const u8) !?Session {
        // List session files for this masque
        var dir = std.fs.cwd().openDir(self.sessions_dir, .{ .iterate = true }) catch {
            return null;
        };
        defer dir.close();

        const prefix = try std.fmt.allocPrint(self.allocator, "{s}-", .{masque_name});
        defer self.allocator.free(prefix);

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind != .file) continue;
            if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
            if (!std.mem.startsWith(u8, entry.name, prefix)) continue;

            // Found a session file for this masque
            const session_id = entry.name[0 .. entry.name.len - 5]; // Remove .json
            return try self.readSessionFile(session_id);
        }

        return null;
    }

    fn writeSessionFile(self: *SessionManager, session: *const Session) !void {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.sessions_dir, session.id });
        defer self.allocator.free(path);

        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();

        // Format to a buffer first, then write
        const content = try std.fmt.allocPrint(
            self.allocator,
            "{{\"id\":\"{s}\",\"masque\":\"{s}\",\"version\":\"{s}\",\"intent\":\"{s}\",\"started_at\":{d},\"ring\":\"{s}\"}}",
            .{
                session.id,
                session.masque_name,
                session.masque_version,
                session.intent,
                session.started_at,
                session.ring,
            },
        );
        defer self.allocator.free(content);
        try file.writeAll(content);
    }

    fn readSessionFile(self: *SessionManager, session_id: []const u8) !Session {
        const path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.json", .{ self.sessions_dir, session_id });
        defer self.allocator.free(path);

        const content = try std.fs.cwd().readFileAlloc(self.allocator, path, 4096);
        defer self.allocator.free(content);

        // Simple JSON parsing (for our known format)
        return Session{
            .id = try self.allocator.dupe(u8, session_id),
            .masque_name = try extractJsonString(self.allocator, content, "masque"),
            .masque_version = try extractJsonString(self.allocator, content, "version"),
            .intent = try extractJsonString(self.allocator, content, "intent"),
            .started_at = extractJsonInt(content, "started_at") orelse 0,
            .ring = try extractJsonString(self.allocator, content, "ring"),
        };
    }
};

fn extractJsonString(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]const u8 {
    // Find "key":"value"
    const search_key = try std.fmt.allocPrint(allocator, "\"{s}\":\"", .{key});
    defer allocator.free(search_key);

    const start_pos = std.mem.indexOf(u8, json, search_key) orelse return error.KeyNotFound;
    const value_start = start_pos + search_key.len;

    // Find closing quote
    var end_pos = value_start;
    while (end_pos < json.len) : (end_pos += 1) {
        if (json[end_pos] == '"' and (end_pos == value_start or json[end_pos - 1] != '\\')) {
            break;
        }
    }

    return try allocator.dupe(u8, json[value_start..end_pos]);
}

fn extractJsonInt(json: []const u8, key: []const u8) ?i64 {
    // Find "key":number
    var buf: [64]u8 = undefined;
    const search_key = std.fmt.bufPrint(&buf, "\"{s}\":", .{key}) catch return null;

    const start_pos = std.mem.indexOf(u8, json, search_key) orelse return null;
    const value_start = start_pos + search_key.len;

    // Find end of number
    var end_pos = value_start;
    while (end_pos < json.len) : (end_pos += 1) {
        const c = json[end_pos];
        if (c != '-' and (c < '0' or c > '9')) break;
    }

    return std.fmt.parseInt(i64, json[value_start..end_pos], 10) catch null;
}

test "session manager" {
    // This test requires a filesystem, so we just test the helper functions
    const json = "{\"id\":\"test-123\",\"masque\":\"codesmith\",\"version\":\"0.1.0\",\"intent\":\"implement parser\",\"started_at\":1234567890,\"ring\":\"player\"}";

    const masque = try extractJsonString(std.testing.allocator, json, "masque");
    defer std.testing.allocator.free(masque);
    try std.testing.expectEqualStrings("codesmith", masque);

    const started = extractJsonInt(json, "started_at");
    try std.testing.expectEqual(@as(i64, 1234567890), started.?);
}
