//! Mesh Coordinator - Unified mesh networking coordinator
//!
//! This module integrates mDNS discovery, connection management, and the wire protocol
//! into a single coordinator that can be used by masque binaries for peer-to-peer
//! communication.

const std = @import("std");
const net = std.net;
const posix = std.posix;

// Import mesh modules - try module imports first (for build system), fallback to file imports (for tests)
const mdns = if (@hasDecl(@import("root"), "mesh"))
    @import("root").mesh.mdns
else
    @import("mdns.zig");
const connection = if (@hasDecl(@import("root"), "mesh"))
    @import("root").mesh.connection
else
    @import("connection.zig");
const protocol = if (@hasDecl(@import("root"), "mesh"))
    @import("root").mesh.protocol
else
    @import("protocol.zig");

pub const MdnsService = mdns.MdnsService;
pub const PeerInfo = mdns.PeerInfo;
pub const ConnectionManager = connection.ConnectionManager;
pub const Connection = connection.Connection;
pub const Message = protocol.Message;
pub const MessageType = protocol.MessageType;
pub const Frame = protocol.Frame;

/// Default port for masque mesh communication
pub const DEFAULT_PORT: u16 = 9475;

/// MeshCoordinator integrates mDNS, connections, and protocol into one interface
pub const MeshCoordinator = struct {
    allocator: std.mem.Allocator,
    mdns_service: ?MdnsService,
    connections: ConnectionManager,
    name: []const u8,
    version: []const u8,
    port: u16,
    listener: ?posix.socket_t,
    running: bool,

    const Self = @This();

    /// Initialize the mesh coordinator
    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8, port: u16) !Self {
        const name_copy = try allocator.dupe(u8, name);
        errdefer allocator.free(name_copy);

        const version_copy = try allocator.dupe(u8, version);
        errdefer allocator.free(version_copy);

        // Initialize mDNS service (may fail on systems without multicast support)
        const mdns_service: ?MdnsService = MdnsService.init(allocator, name, version, port) catch |err| blk: {
            std.log.warn("mDNS service init failed: {}, falling back to manual peer config", .{err});
            break :blk null;
        };
        errdefer if (mdns_service) |m| {
            var mdns_mut = m;
            mdns_mut.deinit();
        };

        return Self{
            .allocator = allocator,
            .mdns_service = mdns_service,
            .connections = ConnectionManager.init(allocator),
            .name = name_copy,
            .version = version_copy,
            .port = port,
            .listener = null,
            .running = false,
        };
    }

    /// Clean up all resources
    pub fn deinit(self: *Self) void {
        self.running = false;

        // Close listener socket
        if (self.listener) |sock| {
            posix.close(sock);
            self.listener = null;
        }

        // Shutdown connections
        self.connections.deinit();

        // Shutdown mDNS
        if (self.mdns_service) |*m| {
            m.deinit();
        }

        self.allocator.free(self.name);
        self.allocator.free(self.version);
    }

    /// Announce this masque's presence on the mesh
    pub fn announce(self: *Self) !void {
        if (self.mdns_service) |*m| {
            try m.announce();
        } else {
            return error.MdnsNotAvailable;
        }
    }

    /// Discover peers on the local network
    /// Returns a slice of PeerInfo that the caller must free
    pub fn discover(self: *Self, timeout_ms: u32) ![]PeerInfo {
        if (self.mdns_service) |*m| {
            return m.browse(timeout_ms);
        } else {
            return error.MdnsNotAvailable;
        }
    }

    /// Get currently known peers without re-browsing
    pub fn getPeers(self: *Self) []PeerInfo {
        if (self.mdns_service) |*m| {
            return m.getPeers();
        }
        return &[_]PeerInfo{};
    }

    /// Send a message to a specific peer
    pub fn sendMessage(self: *Self, peer_name: []const u8, msg: *const Message) !void {
        // Find peer address
        const peer_info = self.findPeer(peer_name) orelse return error.PeerNotFound;

        // Get or create connection to peer
        const conn = try self.connections.connect(peer_name, peer_info.address);

        // Encode message to framed bytes
        const frame_data = try Frame.encode(self.allocator, msg);
        defer self.allocator.free(frame_data);

        // Send the frame
        try conn.send(frame_data);
    }

    /// Send a message with just payload (helper that creates Message internally)
    pub fn sendPayload(
        self: *Self,
        peer_name: []const u8,
        msg_type: MessageType,
        payload: []const u8,
    ) !void {
        var msg_id_buf: [64]u8 = undefined;
        const msg_id = try self.generateMessageId(&msg_id_buf);

        const msg = Message{
            .msg_type = msg_type,
            .from = self.name,
            .to = peer_name,
            .id = msg_id,
            .payload = payload,
            .timestamp = std.time.timestamp(),
        };

        try self.sendMessage(peer_name, &msg);
    }

    /// Start the TCP listener for incoming connections
    pub fn startListener(self: *Self) !void {
        if (self.listener != null) {
            return error.AlreadyListening;
        }

        // Create TCP socket
        const sock = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
        errdefer posix.close(sock);

        // Enable address reuse
        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

        // Bind to port
        const addr = net.Address.initIp4(.{ 0, 0, 0, 0 }, self.port);
        try posix.bind(sock, &addr.any, addr.getOsSockLen());

        // Start listening
        try posix.listen(sock, 16);

        self.listener = sock;
        self.running = true;
    }

    /// Accept and handle one incoming connection
    /// Returns the received message or null if no connection is pending
    pub fn acceptOne(self: *Self) !?Message {
        const listener = self.listener orelse return error.NotListening;

        // Accept connection
        var client_addr: posix.sockaddr.storage = undefined;
        var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);

        const client_sock = posix.accept(listener, @ptrCast(&client_addr), &addr_len, 0) catch |err| {
            if (err == error.WouldBlock) {
                return null;
            }
            return err;
        };
        defer posix.close(client_sock);

        // Read frame from connection using direct socket read
        const payload = try readFrameFromSocket(client_sock, self.allocator, protocol.max_message_size);
        defer self.allocator.free(payload);

        // Decode message
        return try Message.deserialize(self.allocator, payload);
    }

    /// Read a framed message from a socket
    fn readFrameFromSocket(sock: posix.socket_t, allocator: std.mem.Allocator, max_size: usize) ![]u8 {
        // Read 4-byte length header
        var len_buf: [4]u8 = undefined;
        var total_read: usize = 0;
        while (total_read < 4) {
            const bytes = posix.read(sock, len_buf[total_read..]) catch |err| {
                if (err == error.WouldBlock) continue;
                return err;
            };
            if (bytes == 0) return error.UnexpectedEof;
            total_read += bytes;
        }

        // Parse big-endian length
        const len: u32 = (@as(u32, len_buf[0]) << 24) |
            (@as(u32, len_buf[1]) << 16) |
            (@as(u32, len_buf[2]) << 8) |
            @as(u32, len_buf[3]);

        const effective_max = @min(max_size, protocol.max_message_size);
        if (len > effective_max) return error.MessageTooLarge;

        // Read payload
        const payload = try allocator.alloc(u8, len);
        errdefer allocator.free(payload);

        var payload_read: usize = 0;
        while (payload_read < len) {
            const bytes = posix.read(sock, payload[payload_read..]) catch |err| {
                if (err == error.WouldBlock) continue;
                allocator.free(payload);
                return err;
            };
            if (bytes == 0) {
                allocator.free(payload);
                return error.UnexpectedEof;
            }
            payload_read += bytes;
        }

        return payload;
    }

    /// Run the listener loop, calling handler for each message
    pub fn runListener(self: *Self, handler: *const fn (*Self, Message) void) !void {
        try self.startListener();

        while (self.running) {
            if (try self.acceptOne()) |msg| {
                var message = msg;
                defer message.deinit(self.allocator);
                handler(self, message);
            }

            // Small sleep to avoid busy-waiting
            std.time.sleep(10 * std.time.ns_per_ms);
        }
    }

    /// Stop the listener
    pub fn stopListener(self: *Self) void {
        self.running = false;
        if (self.listener) |sock| {
            posix.close(sock);
            self.listener = null;
        }
    }

    /// Perform health checks on all connections
    pub fn healthCheck(self: *Self) void {
        self.connections.healthCheck();

        // Also prune stale mDNS peers
        if (self.mdns_service) |*m| {
            m.pruneStale(300); // 5 minute timeout
        }
    }

    /// Find a peer by name in the discovered peers
    fn findPeer(self: *Self, peer_name: []const u8) ?PeerInfo {
        if (self.mdns_service) |*m| {
            const peers = m.getPeers();
            defer self.allocator.free(peers);

            for (peers) |peer| {
                if (std.mem.eql(u8, peer.name, peer_name)) {
                    return peer;
                }
            }
        }
        return null;
    }

    /// Generate a unique message ID
    fn generateMessageId(self: *Self, buf: []u8) ![]const u8 {
        const timestamp = std.time.milliTimestamp();

        return std.fmt.bufPrint(buf, "{s}-{d}", .{
            self.name,
            timestamp,
        }) catch return error.BufferTooSmall;
    }
};

// ============================================================================
// Tests
// ============================================================================

test "MeshCoordinator init and deinit" {
    const allocator = std.testing.allocator;

    // Note: mDNS may fail without permissions, but coordinator should still work
    var coord = MeshCoordinator.init(allocator, "test-masque", "1.0.0", 9999) catch |err| {
        std.debug.print("MeshCoordinator.init failed (may need permissions): {}\n", .{err});
        return;
    };
    defer coord.deinit();

    try std.testing.expectEqualStrings("test-masque", coord.name);
    try std.testing.expectEqualStrings("1.0.0", coord.version);
    try std.testing.expectEqual(@as(u16, 9999), coord.port);
    try std.testing.expect(!coord.running);
}

test "MeshCoordinator generateMessageId" {
    const allocator = std.testing.allocator;

    var coord = MeshCoordinator.init(allocator, "test", "1.0.0", 9999) catch {
        return; // Skip if init fails
    };
    defer coord.deinit();

    var buf: [64]u8 = undefined;
    const id = try coord.generateMessageId(&buf);

    // ID should start with the masque name
    try std.testing.expect(std.mem.startsWith(u8, id, "test-"));
    try std.testing.expect(id.len > 10);
}

test "MeshCoordinator stopListener when not listening" {
    const allocator = std.testing.allocator;

    var coord = MeshCoordinator.init(allocator, "test", "1.0.0", 9999) catch {
        return;
    };
    defer coord.deinit();

    // Should not crash when stopping a non-running listener
    coord.stopListener();
    try std.testing.expect(!coord.running);
}

test "MeshCoordinator getPeers when mdns not available" {
    const allocator = std.testing.allocator;

    var coord = MeshCoordinator{
        .allocator = allocator,
        .mdns_service = null, // Explicitly no mDNS
        .connections = ConnectionManager.init(allocator),
        .name = "test",
        .version = "1.0.0",
        .port = 9999,
        .listener = null,
        .running = false,
    };
    defer coord.connections.deinit();

    const peers = coord.getPeers();
    try std.testing.expectEqual(@as(usize, 0), peers.len);
}

test "DEFAULT_PORT value" {
    try std.testing.expectEqual(@as(u16, 9475), DEFAULT_PORT);
}
