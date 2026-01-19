const std = @import("std");
const posix = std.posix;
const net = std.net;

/// Connection states for the state machine
pub const ConnectionState = enum {
    connecting,
    connected,
    disconnected,
    reconnecting,
};

/// Reconnection configuration constants
pub const ReconnectConfig = struct {
    pub const initial_backoff_ms: u64 = 100;
    pub const max_backoff_ms: u64 = 30_000;
    pub const backoff_multiplier: u64 = 2;
    pub const max_attempts: u32 = 10;
};

/// Health check configuration constants
pub const HealthConfig = struct {
    pub const ping_interval_ms: i64 = 30_000;
    pub const pong_timeout_ms: i64 = 5_000;
};

/// A single TCP connection to a peer
pub const Connection = struct {
    stream: ?net.Stream,
    peer_id: []const u8,
    address: net.Address,
    state: ConnectionState,
    last_activity: i64,
    reconnect_attempts: u32,
    allocator: std.mem.Allocator,
    awaiting_pong: bool,
    pong_deadline: i64,

    const Self = @This();

    /// Initialize a new connection (does not connect)
    pub fn init(allocator: std.mem.Allocator, peer_id: []const u8, address: net.Address) !*Self {
        const conn = try allocator.create(Self);
        const id_copy = try allocator.dupe(u8, peer_id);

        conn.* = .{
            .stream = null,
            .peer_id = id_copy,
            .address = address,
            .state = .disconnected,
            .last_activity = std.time.milliTimestamp(),
            .reconnect_attempts = 0,
            .allocator = allocator,
            .awaiting_pong = false,
            .pong_deadline = 0,
        };

        return conn;
    }

    /// Clean up connection resources
    pub fn deinit(self: *Self) void {
        self.close();
        self.allocator.free(self.peer_id);
        self.allocator.destroy(self);
    }

    /// Attempt to establish the TCP connection
    pub fn connect(self: *Self) !void {
        if (self.state == .connected and self.stream != null) {
            return;
        }

        self.state = .connecting;

        const stream = net.tcpConnectToAddress(self.address) catch |err| {
            self.state = .disconnected;
            return err;
        };

        self.stream = stream;
        self.state = .connected;
        self.last_activity = std.time.milliTimestamp();
        self.reconnect_attempts = 0;
        self.awaiting_pong = false;
    }

    /// Send data over the connection
    pub fn send(self: *Self, data: []const u8) !void {
        if (self.state != .connected) {
            return error.NotConnected;
        }

        const stream = self.stream orelse return error.NotConnected;
        try stream.writeAll(data);
        self.last_activity = std.time.milliTimestamp();
    }

    /// Receive data from the connection
    pub fn receive(self: *Self, buffer: []u8) !usize {
        if (self.state != .connected) {
            return error.NotConnected;
        }

        const stream = self.stream orelse return error.NotConnected;
        const bytes_read = try stream.read(buffer);

        if (bytes_read > 0) {
            self.last_activity = std.time.milliTimestamp();
        }

        return bytes_read;
    }

    /// Close the connection
    pub fn close(self: *Self) void {
        if (self.stream) |stream| {
            stream.close();
            self.stream = null;
        }
        self.state = .disconnected;
        self.awaiting_pong = false;
    }

    /// Calculate backoff time for reconnection
    pub fn getBackoffMs(self: *const Self) u64 {
        if (self.reconnect_attempts == 0) {
            return ReconnectConfig.initial_backoff_ms;
        }

        var backoff = ReconnectConfig.initial_backoff_ms;
        var i: u32 = 0;
        while (i < self.reconnect_attempts) : (i += 1) {
            backoff *= ReconnectConfig.backoff_multiplier;
            if (backoff >= ReconnectConfig.max_backoff_ms) {
                return ReconnectConfig.max_backoff_ms;
            }
        }
        return backoff;
    }

    /// Attempt reconnection with exponential backoff
    pub fn attemptReconnect(self: *Self) !void {
        if (self.reconnect_attempts >= ReconnectConfig.max_attempts) {
            return error.MaxReconnectAttemptsExceeded;
        }

        self.state = .reconnecting;
        self.reconnect_attempts += 1;

        // Calculate and wait for backoff
        const backoff_ms = self.getBackoffMs();
        std.time.sleep(backoff_ms * std.time.ns_per_ms);

        // Attempt to connect
        self.connect() catch |err| {
            self.state = .disconnected;
            return err;
        };
    }

    /// Check if connection needs a ping (idle check)
    pub fn needsPing(self: *const Self) bool {
        if (self.state != .connected or self.awaiting_pong) {
            return false;
        }

        const now = std.time.milliTimestamp();
        const idle_time = now - self.last_activity;
        return idle_time >= HealthConfig.ping_interval_ms;
    }

    /// Send a ping message
    pub fn sendPing(self: *Self) !void {
        if (self.state != .connected) {
            return error.NotConnected;
        }

        // Simple ping protocol: send "PING\n"
        try self.send("PING\n");
        self.awaiting_pong = true;
        self.pong_deadline = std.time.milliTimestamp() + HealthConfig.pong_timeout_ms;
    }

    /// Check if pong timeout has occurred
    pub fn isPongTimedOut(self: *const Self) bool {
        if (!self.awaiting_pong) {
            return false;
        }

        const now = std.time.milliTimestamp();
        return now >= self.pong_deadline;
    }

    /// Handle received pong
    pub fn handlePong(self: *Self) void {
        self.awaiting_pong = false;
        self.last_activity = std.time.milliTimestamp();
    }
};

/// Manages a pool of connections to peers
pub const ConnectionManager = struct {
    allocator: std.mem.Allocator,
    connections: std.StringHashMap(*Connection),
    max_connections_per_peer: usize,
    shutdown_requested: bool,

    const Self = @This();

    /// Initialize the connection manager
    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .connections = std.StringHashMap(*Connection).init(allocator),
            .max_connections_per_peer = 1, // Default to 1 connection per peer
            .shutdown_requested = false,
        };
    }

    /// Initialize with custom max connections per peer
    pub fn initWithConfig(allocator: std.mem.Allocator, max_connections_per_peer: usize) Self {
        var mgr = init(allocator);
        mgr.max_connections_per_peer = max_connections_per_peer;
        return mgr;
    }

    /// Clean up all connections and resources
    pub fn deinit(self: *Self) void {
        self.shutdown_requested = true;

        var iter = self.connections.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.deinit();
        }
        self.connections.deinit();
    }

    /// Connect to a peer at the given address
    pub fn connect(self: *Self, peer_id: []const u8, address: net.Address) !*Connection {
        if (self.shutdown_requested) {
            return error.ShutdownInProgress;
        }

        // Check if we already have a connection to this peer
        if (self.connections.get(peer_id)) |existing| {
            if (existing.state == .connected) {
                return existing;
            }
            // Try to reconnect existing connection
            try existing.connect();
            return existing;
        }

        // Check max connections limit (simplified: 1 connection per peer for now)
        if (self.connections.count() >= self.max_connections_per_peer * 100) {
            return error.TooManyConnections;
        }

        // Create new connection
        const conn = try Connection.init(self.allocator, peer_id, address);
        errdefer conn.deinit();

        // Attempt to connect
        try conn.connect();

        // Store in map (need to dupe the key since Connection owns its peer_id)
        const key_copy = try self.allocator.dupe(u8, peer_id);
        errdefer self.allocator.free(key_copy);

        try self.connections.put(key_copy, conn);

        return conn;
    }

    /// Disconnect from a peer
    pub fn disconnect(self: *Self, peer_id: []const u8) void {
        if (self.connections.fetchRemove(peer_id)) |kv| {
            kv.value.deinit();
            self.allocator.free(kv.key);
        }
    }

    /// Get an existing connection by peer ID
    pub fn getConnection(self: *Self, peer_id: []const u8) ?*Connection {
        return self.connections.get(peer_id);
    }

    /// Perform health checks on all connections
    pub fn healthCheck(self: *Self) void {
        var to_remove: std.ArrayList([]const u8) = .empty;
        defer to_remove.deinit(self.allocator);

        var iter = self.connections.iterator();
        while (iter.next()) |entry| {
            const conn = entry.value_ptr.*;

            // Check for pong timeout
            if (conn.isPongTimedOut()) {
                conn.close();
                to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
                continue;
            }

            // Send ping if needed
            if (conn.needsPing()) {
                conn.sendPing() catch {
                    conn.close();
                    to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
                    continue;
                };
            }
        }

        // Remove unhealthy connections
        for (to_remove.items) |peer_id| {
            self.disconnect(peer_id);
        }
    }

    /// Attempt to reconnect disconnected connections
    pub fn reconnectDisconnected(self: *Self) void {
        var iter = self.connections.iterator();
        while (iter.next()) |entry| {
            const conn = entry.value_ptr.*;

            if (conn.state == .disconnected) {
                conn.attemptReconnect() catch {
                    // Connection failed, will try again later
                    continue;
                };
            }
        }
    }

    /// Get the number of active connections
    pub fn activeConnectionCount(self: *Self) usize {
        var count: usize = 0;
        var iter = self.connections.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.*.state == .connected) {
                count += 1;
            }
        }
        return count;
    }

    /// Get total connection count (all states)
    pub fn totalConnectionCount(self: *Self) usize {
        return self.connections.count();
    }

    /// Initiate graceful shutdown
    pub fn shutdown(self: *Self) void {
        self.shutdown_requested = true;

        var iter = self.connections.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.*.close();
        }
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Connection init and deinit" {
    const allocator = std.testing.allocator;
    const address = net.Address.initIp4(.{ 127, 0, 0, 1 }, 8080);

    const conn = try Connection.init(allocator, "test-peer", address);
    defer conn.deinit();

    try std.testing.expectEqualStrings("test-peer", conn.peer_id);
    try std.testing.expectEqual(ConnectionState.disconnected, conn.state);
    try std.testing.expectEqual(@as(u32, 0), conn.reconnect_attempts);
}

test "Connection backoff calculation" {
    const allocator = std.testing.allocator;
    const address = net.Address.initIp4(.{ 127, 0, 0, 1 }, 8080);

    const conn = try Connection.init(allocator, "test-peer", address);
    defer conn.deinit();

    // Initial backoff
    try std.testing.expectEqual(@as(u64, 100), conn.getBackoffMs());

    // Simulate reconnect attempts
    conn.reconnect_attempts = 1;
    try std.testing.expectEqual(@as(u64, 200), conn.getBackoffMs());

    conn.reconnect_attempts = 2;
    try std.testing.expectEqual(@as(u64, 400), conn.getBackoffMs());

    conn.reconnect_attempts = 3;
    try std.testing.expectEqual(@as(u64, 800), conn.getBackoffMs());

    // Should cap at max backoff
    conn.reconnect_attempts = 20;
    try std.testing.expectEqual(@as(u64, 30_000), conn.getBackoffMs());
}

test "Connection needsPing" {
    const allocator = std.testing.allocator;
    const address = net.Address.initIp4(.{ 127, 0, 0, 1 }, 8080);

    const conn = try Connection.init(allocator, "test-peer", address);
    defer conn.deinit();

    // Not connected, shouldn't need ping
    try std.testing.expect(!conn.needsPing());

    // Simulate connected state with recent activity
    conn.state = .connected;
    conn.last_activity = std.time.milliTimestamp();
    try std.testing.expect(!conn.needsPing());

    // Simulate idle connection (set last_activity far in the past)
    conn.last_activity = std.time.milliTimestamp() - HealthConfig.ping_interval_ms - 1000;
    try std.testing.expect(conn.needsPing());

    // Already awaiting pong
    conn.awaiting_pong = true;
    try std.testing.expect(!conn.needsPing());
}

test "Connection pong timeout" {
    const allocator = std.testing.allocator;
    const address = net.Address.initIp4(.{ 127, 0, 0, 1 }, 8080);

    const conn = try Connection.init(allocator, "test-peer", address);
    defer conn.deinit();

    // Not awaiting pong
    try std.testing.expect(!conn.isPongTimedOut());

    // Awaiting pong with future deadline
    conn.awaiting_pong = true;
    conn.pong_deadline = std.time.milliTimestamp() + 10_000;
    try std.testing.expect(!conn.isPongTimedOut());

    // Awaiting pong with past deadline
    conn.pong_deadline = std.time.milliTimestamp() - 1000;
    try std.testing.expect(conn.isPongTimedOut());

    // Handle pong clears the flag
    conn.handlePong();
    try std.testing.expect(!conn.awaiting_pong);
    try std.testing.expect(!conn.isPongTimedOut());
}

test "ConnectionManager init and deinit" {
    const allocator = std.testing.allocator;

    var mgr = ConnectionManager.init(allocator);
    defer mgr.deinit();

    try std.testing.expectEqual(@as(usize, 1), mgr.max_connections_per_peer);
    try std.testing.expectEqual(@as(usize, 0), mgr.totalConnectionCount());
}

test "ConnectionManager initWithConfig" {
    const allocator = std.testing.allocator;

    var mgr = ConnectionManager.initWithConfig(allocator, 5);
    defer mgr.deinit();

    try std.testing.expectEqual(@as(usize, 5), mgr.max_connections_per_peer);
}

test "ConnectionManager getConnection returns null for unknown peer" {
    const allocator = std.testing.allocator;

    var mgr = ConnectionManager.init(allocator);
    defer mgr.deinit();

    try std.testing.expect(mgr.getConnection("unknown-peer") == null);
}

test "ConnectionManager shutdown flag" {
    const allocator = std.testing.allocator;

    var mgr = ConnectionManager.init(allocator);
    defer mgr.deinit();

    try std.testing.expect(!mgr.shutdown_requested);

    mgr.shutdown();

    try std.testing.expect(mgr.shutdown_requested);
}

test "ConnectionManager activeConnectionCount" {
    const allocator = std.testing.allocator;

    var mgr = ConnectionManager.init(allocator);
    defer mgr.deinit();

    try std.testing.expectEqual(@as(usize, 0), mgr.activeConnectionCount());
}

test "ConnectionState enum values" {
    try std.testing.expectEqual(@as(usize, 4), @typeInfo(ConnectionState).@"enum".fields.len);
}

test "ReconnectConfig values" {
    try std.testing.expectEqual(@as(u64, 100), ReconnectConfig.initial_backoff_ms);
    try std.testing.expectEqual(@as(u64, 30_000), ReconnectConfig.max_backoff_ms);
    try std.testing.expectEqual(@as(u64, 2), ReconnectConfig.backoff_multiplier);
    try std.testing.expectEqual(@as(u32, 10), ReconnectConfig.max_attempts);
}

test "HealthConfig values" {
    try std.testing.expectEqual(@as(i64, 30_000), HealthConfig.ping_interval_ms);
    try std.testing.expectEqual(@as(i64, 5_000), HealthConfig.pong_timeout_ms);
}
