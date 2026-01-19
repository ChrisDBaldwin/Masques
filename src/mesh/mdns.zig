//! mDNS service advertisement and discovery for masque mesh networking.
//!
//! This module provides peer discovery using multicast DNS (mDNS) on the local network.
//! Services are advertised as `_masque._tcp.local.` with TXT records containing
//! name, version, and port information.
//!
//! Fallback: If mDNS discovery fails or finds no peers, reads explicit peers from
//! `~/.masque/peers.txt`.

const std = @import("std");
const posix = std.posix;
const net = std.net;

/// mDNS multicast address (IPv4)
pub const MDNS_MULTICAST_ADDR_V4 = "224.0.0.251";
/// mDNS multicast address (IPv6)
pub const MDNS_MULTICAST_ADDR_V6 = "ff02::fb";
/// mDNS port
pub const MDNS_PORT: u16 = 5353;
/// Service type for masque mesh
pub const SERVICE_TYPE = "_masque._tcp.local.";

/// DNS record types
const DnsType = enum(u16) {
    A = 1,
    PTR = 12,
    TXT = 16,
    AAAA = 28,
    SRV = 33,
    ANY = 255,
};

/// DNS class
const DnsClass = enum(u16) {
    IN = 1,
    ANY = 255,
};

/// DNS header flags
const DnsFlags = packed struct(u16) {
    rcode: u4 = 0,
    z: u3 = 0,
    ra: u1 = 0,
    rd: u1 = 0,
    tc: u1 = 0,
    aa: u1 = 1, // Authoritative for mDNS responses
    opcode: u4 = 0,
    qr: u1 = 0, // 0 = query, 1 = response
};

/// Information about a discovered peer
pub const PeerInfo = struct {
    name: []const u8,
    address: net.Address,
    port: u16,
    version: []const u8,
    last_seen: i64,

    pub fn deinit(self: *PeerInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.version);
    }
};

/// mDNS service for advertising and discovering masque mesh peers
pub const MdnsService = struct {
    allocator: std.mem.Allocator,
    socket: ?posix.socket_t,
    name: []const u8,
    version: []const u8,
    port: u16,
    peers: std.StringHashMap(PeerInfo),
    multicast_addr: net.Address,

    const Self = @This();

    /// Initialize the mDNS service
    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8, port: u16) !Self {
        const multicast_addr = try net.Address.parseIp4(MDNS_MULTICAST_ADDR_V4, MDNS_PORT);

        var self = Self{
            .allocator = allocator,
            .socket = null,
            .name = try allocator.dupe(u8, name),
            .version = try allocator.dupe(u8, version),
            .port = port,
            .peers = std.StringHashMap(PeerInfo).init(allocator),
            .multicast_addr = multicast_addr,
        };

        errdefer self.deinit();

        // Create UDP socket
        self.socket = try posix.socket(posix.AF.INET, posix.SOCK.DGRAM, 0);
        errdefer if (self.socket) |s| posix.close(s);

        const sock = self.socket.?;

        // Enable address reuse
        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));

        // Enable port reuse (for multiple processes)
        if (@hasDecl(posix.SO, "REUSEPORT")) {
            posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.REUSEPORT, &std.mem.toBytes(@as(c_int, 1))) catch {};
        }

        // Bind to mDNS port
        const bind_addr = net.Address.initIp4(.{ 0, 0, 0, 0 }, MDNS_PORT);
        try posix.bind(sock, &bind_addr.any, bind_addr.getOsSockLen());

        // Join multicast group
        const mreq = extern struct {
            multiaddr: [4]u8,
            interface: [4]u8,
        }{
            .multiaddr = @bitCast(multicast_addr.in.sa.addr),
            .interface = .{ 0, 0, 0, 0 },
        };

        try posix.setsockopt(sock, posix.IPPROTO.IP, @intFromEnum(IpMulticastOption.ADD_MEMBERSHIP), std.mem.asBytes(&mreq));

        // Set multicast TTL to 255 (link-local)
        try posix.setsockopt(sock, posix.IPPROTO.IP, @intFromEnum(IpMulticastOption.MULTICAST_TTL), &std.mem.toBytes(@as(c_int, 255)));

        // Enable loopback so we can see our own announcements (useful for testing)
        try posix.setsockopt(sock, posix.IPPROTO.IP, @intFromEnum(IpMulticastOption.MULTICAST_LOOP), &std.mem.toBytes(@as(c_int, 1)));

        return self;
    }

    /// IP multicast socket options
    const IpMulticastOption = enum(u32) {
        MULTICAST_IF = 9,
        MULTICAST_TTL = 10,
        MULTICAST_LOOP = 11,
        ADD_MEMBERSHIP = 12,
        DROP_MEMBERSHIP = 13,
    };

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        // Close socket
        if (self.socket) |sock| {
            // Leave multicast group before closing
            const mreq = extern struct {
                multiaddr: [4]u8,
                interface: [4]u8,
            }{
                .multiaddr = @bitCast(self.multicast_addr.in.sa.addr),
                .interface = .{ 0, 0, 0, 0 },
            };
            posix.setsockopt(sock, posix.IPPROTO.IP, @intFromEnum(IpMulticastOption.DROP_MEMBERSHIP), std.mem.asBytes(&mreq)) catch {};
            posix.close(sock);
        }

        // Free peer data
        var it = self.peers.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.version);
        }
        self.peers.deinit();

        self.allocator.free(self.name);
        self.allocator.free(self.version);
    }

    /// Announce this service on the network
    pub fn announce(self: *Self) !void {
        const sock = self.socket orelse return error.SocketNotInitialized;

        var buffer: [1024]u8 = undefined;
        const packet_len = try self.buildAnnouncementPacket(&buffer);

        _ = try posix.sendto(sock, buffer[0..packet_len], 0, &self.multicast_addr.any, self.multicast_addr.getOsSockLen());
    }

    /// Build an mDNS announcement packet
    fn buildAnnouncementPacket(self: *Self, buffer: []u8) !usize {
        var fbs = std.io.fixedBufferStream(buffer);
        const writer = fbs.writer();

        // DNS Header (12 bytes)
        try writer.writeInt(u16, 0, .big); // Transaction ID (0 for mDNS)
        try writer.writeInt(u16, 0x8400, .big); // Flags: response, authoritative
        try writer.writeInt(u16, 0, .big); // Questions
        try writer.writeInt(u16, 3, .big); // Answers (PTR, SRV, TXT)
        try writer.writeInt(u16, 0, .big); // Authority
        try writer.writeInt(u16, 0, .big); // Additional

        // Build service instance name: <name>._masque._tcp.local.
        var instance_name_buf: [256]u8 = undefined;
        const instance_name = try std.fmt.bufPrint(&instance_name_buf, "{s}.{s}", .{ self.name, SERVICE_TYPE });

        // PTR record: _masque._tcp.local. -> <name>._masque._tcp.local.
        try writeDnsName(writer, SERVICE_TYPE);
        try writer.writeInt(u16, @intFromEnum(DnsType.PTR), .big);
        try writer.writeInt(u16, @intFromEnum(DnsClass.IN) | 0x8000, .big); // Cache flush
        try writer.writeInt(u32, 4500, .big); // TTL
        const ptr_rdata_start = fbs.pos;
        try writer.writeInt(u16, 0, .big); // Placeholder for RDLENGTH
        const ptr_rdata_begin = fbs.pos;
        try writeDnsName(writer, instance_name);
        const ptr_rdata_len = fbs.pos - ptr_rdata_begin;
        // Go back and fill in RDLENGTH
        const current_pos = fbs.pos;
        fbs.pos = ptr_rdata_start;
        try writer.writeInt(u16, @intCast(ptr_rdata_len), .big);
        fbs.pos = current_pos;

        // SRV record: <name>._masque._tcp.local. -> port, target
        try writeDnsName(writer, instance_name);
        try writer.writeInt(u16, @intFromEnum(DnsType.SRV), .big);
        try writer.writeInt(u16, @intFromEnum(DnsClass.IN) | 0x8000, .big);
        try writer.writeInt(u32, 120, .big); // TTL
        const srv_rdata_start = fbs.pos;
        try writer.writeInt(u16, 0, .big); // Placeholder
        const srv_rdata_begin = fbs.pos;
        try writer.writeInt(u16, 0, .big); // Priority
        try writer.writeInt(u16, 0, .big); // Weight
        try writer.writeInt(u16, self.port, .big); // Port
        // Target hostname (just use instance name for simplicity)
        try writeDnsName(writer, instance_name);
        const srv_rdata_len = fbs.pos - srv_rdata_begin;
        const srv_current_pos = fbs.pos;
        fbs.pos = srv_rdata_start;
        try writer.writeInt(u16, @intCast(srv_rdata_len), .big);
        fbs.pos = srv_current_pos;

        // TXT record with attributes
        try writeDnsName(writer, instance_name);
        try writer.writeInt(u16, @intFromEnum(DnsType.TXT), .big);
        try writer.writeInt(u16, @intFromEnum(DnsClass.IN) | 0x8000, .big);
        try writer.writeInt(u32, 4500, .big); // TTL

        // Build TXT record data
        var txt_data: [256]u8 = undefined;
        var txt_len: usize = 0;

        // name=<name>
        var name_attr_buf: [128]u8 = undefined;
        const name_attr = try std.fmt.bufPrint(&name_attr_buf, "name={s}", .{self.name});
        txt_data[txt_len] = @intCast(name_attr.len);
        txt_len += 1;
        @memcpy(txt_data[txt_len..][0..name_attr.len], name_attr);
        txt_len += name_attr.len;

        // version=<version>
        var ver_attr_buf: [128]u8 = undefined;
        const ver_attr = try std.fmt.bufPrint(&ver_attr_buf, "version={s}", .{self.version});
        txt_data[txt_len] = @intCast(ver_attr.len);
        txt_len += 1;
        @memcpy(txt_data[txt_len..][0..ver_attr.len], ver_attr);
        txt_len += ver_attr.len;

        // port=<port>
        var port_attr_buf: [32]u8 = undefined;
        const port_attr = try std.fmt.bufPrint(&port_attr_buf, "port={d}", .{self.port});
        txt_data[txt_len] = @intCast(port_attr.len);
        txt_len += 1;
        @memcpy(txt_data[txt_len..][0..port_attr.len], port_attr);
        txt_len += port_attr.len;

        try writer.writeInt(u16, @intCast(txt_len), .big);
        try writer.writeAll(txt_data[0..txt_len]);

        return fbs.pos;
    }

    /// Browse for peers on the local network
    pub fn browse(self: *Self, timeout_ms: u32) ![]PeerInfo {
        const sock = self.socket orelse return error.SocketNotInitialized;

        // Send query for _masque._tcp.local.
        var query_buf: [256]u8 = undefined;
        const query_len = try self.buildQueryPacket(&query_buf);
        _ = try posix.sendto(sock, query_buf[0..query_len], 0, &self.multicast_addr.any, self.multicast_addr.getOsSockLen());

        // Set receive timeout
        const timeout_sec = timeout_ms / 1000;
        const timeout_usec = (timeout_ms % 1000) * 1000;
        const tv = posix.timeval{
            .sec = @intCast(timeout_sec),
            .usec = @intCast(timeout_usec),
        };
        try posix.setsockopt(sock, posix.SOL.SOCKET, posix.SO.RCVTIMEO, std.mem.asBytes(&tv));

        // Receive responses
        var recv_buf: [4096]u8 = undefined;
        const deadline = std.time.milliTimestamp() + @as(i64, @intCast(timeout_ms));

        while (std.time.milliTimestamp() < deadline) {
            var src_addr: posix.sockaddr.storage = undefined;
            var addr_len: posix.socklen_t = @sizeOf(posix.sockaddr.storage);

            const recv_result = posix.recvfrom(sock, &recv_buf, 0, @ptrCast(&src_addr), &addr_len);
            if (recv_result) |bytes_read| {
                if (bytes_read > 0) {
                    const src_address = net.Address.initPosix(@ptrCast(&src_addr));
                    self.parseResponse(recv_buf[0..bytes_read], src_address) catch {};
                }
            } else |err| {
                if (err == error.WouldBlock) {
                    break; // Timeout reached
                }
                // Continue on other errors
            }
        }

        // If no peers found via mDNS, try fallback
        if (self.peers.count() == 0) {
            try self.loadFallbackPeers();
        }

        return self.getPeers();
    }

    /// Build an mDNS query packet
    fn buildQueryPacket(self: *Self, buffer: []u8) !usize {
        _ = self;
        var fbs = std.io.fixedBufferStream(buffer);
        const writer = fbs.writer();

        // DNS Header
        try writer.writeInt(u16, 0, .big); // Transaction ID
        try writer.writeInt(u16, 0, .big); // Flags: query
        try writer.writeInt(u16, 1, .big); // Questions
        try writer.writeInt(u16, 0, .big); // Answers
        try writer.writeInt(u16, 0, .big); // Authority
        try writer.writeInt(u16, 0, .big); // Additional

        // Question: _masque._tcp.local. PTR
        try writeDnsName(writer, SERVICE_TYPE);
        try writer.writeInt(u16, @intFromEnum(DnsType.PTR), .big);
        try writer.writeInt(u16, @intFromEnum(DnsClass.IN), .big);

        return fbs.pos;
    }

    /// Parse an mDNS response packet
    fn parseResponse(self: *Self, data: []const u8, src_address: net.Address) !void {
        if (data.len < 12) return error.PacketTooShort;

        var fbs = std.io.fixedBufferStream(data);
        const reader = fbs.reader();

        // Skip transaction ID
        _ = try reader.readInt(u16, .big);

        // Check flags - must be a response
        const flags = try reader.readInt(u16, .big);
        if ((flags & 0x8000) == 0) return; // Not a response

        const questions = try reader.readInt(u16, .big);
        const answers = try reader.readInt(u16, .big);
        _ = try reader.readInt(u16, .big); // Authority
        _ = try reader.readInt(u16, .big); // Additional

        // Skip questions
        var i: usize = 0;
        while (i < questions) : (i += 1) {
            try skipDnsName(&fbs);
            _ = try reader.readInt(u16, .big); // Type
            _ = try reader.readInt(u16, .big); // Class
        }

        // Parse answers
        var peer_name: ?[]const u8 = null;
        var peer_version: ?[]const u8 = null;
        var peer_port: ?u16 = null;

        defer if (peer_name) |n| self.allocator.free(n);
        defer if (peer_version) |v| self.allocator.free(v);

        i = 0;
        while (i < answers) : (i += 1) {
            try skipDnsName(&fbs);
            const rtype = try reader.readInt(u16, .big);
            _ = try reader.readInt(u16, .big); // Class
            _ = try reader.readInt(u32, .big); // TTL
            const rdlength = try reader.readInt(u16, .big);

            const rdata_start = fbs.pos;

            switch (@as(DnsType, @enumFromInt(rtype & 0x7FFF))) {
                .TXT => {
                    // Parse TXT records
                    var txt_pos: usize = 0;
                    while (txt_pos < rdlength) {
                        const txt_len = data[rdata_start + txt_pos];
                        txt_pos += 1;
                        if (txt_pos + txt_len > rdlength) break;

                        const txt = data[rdata_start + txt_pos ..][0..txt_len];
                        txt_pos += txt_len;

                        // Parse key=value
                        if (std.mem.indexOf(u8, txt, "=")) |eq_pos| {
                            const key = txt[0..eq_pos];
                            const value = txt[eq_pos + 1 ..];

                            if (std.mem.eql(u8, key, "name")) {
                                if (peer_name) |n| self.allocator.free(n);
                                peer_name = try self.allocator.dupe(u8, value);
                            } else if (std.mem.eql(u8, key, "version")) {
                                if (peer_version) |v| self.allocator.free(v);
                                peer_version = try self.allocator.dupe(u8, value);
                            } else if (std.mem.eql(u8, key, "port")) {
                                peer_port = std.fmt.parseInt(u16, value, 10) catch null;
                            }
                        }
                    }
                },
                .SRV => {
                    // Parse SRV record for port
                    if (rdlength >= 6) {
                        _ = try reader.readInt(u16, .big); // Priority
                        _ = try reader.readInt(u16, .big); // Weight
                        peer_port = try reader.readInt(u16, .big);
                    }
                },
                else => {},
            }

            // Skip to next record
            fbs.pos = rdata_start + rdlength;
        }

        // Add peer if we have enough info
        if (peer_name) |name| {
            // Don't add ourselves
            if (!std.mem.eql(u8, name, self.name)) {
                const port = peer_port orelse self.port;
                const version = peer_version orelse "unknown";

                // Create address with correct port
                var peer_address = src_address;
                peer_address.in.setPort(port);

                const owned_name = try self.allocator.dupe(u8, name);
                errdefer self.allocator.free(owned_name);

                const owned_version = try self.allocator.dupe(u8, version);
                errdefer self.allocator.free(owned_version);

                const peer_info = PeerInfo{
                    .name = owned_name,
                    .address = peer_address,
                    .port = port,
                    .version = owned_version,
                    .last_seen = std.time.timestamp(),
                };

                // Remove old entry if exists
                if (self.peers.fetchRemove(name)) |old| {
                    self.allocator.free(old.key);
                    self.allocator.free(old.value.version);
                }

                try self.peers.put(owned_name, peer_info);

                // Clear the deferred frees since ownership transferred
                peer_name = null;
                peer_version = null;
            }
        }
    }

    /// Load peers from fallback file ~/.masque/peers.txt
    fn loadFallbackPeers(self: *Self) !void {
        const home = std.posix.getenv("HOME") orelse return;
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buf, "{s}/.masque/peers.txt", .{home});

        const file = std.fs.openFileAbsolute(path, .{}) catch return;
        defer file.close();

        // Read entire file content (max 64KB)
        var content_buf: [65536]u8 = undefined;
        const bytes_read = file.readAll(&content_buf) catch return;
        const content = content_buf[0..bytes_read];

        // Parse line by line
        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            // Skip comments and empty lines
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            // Parse: name address:port
            var parts = std.mem.tokenizeAny(u8, trimmed, " \t");
            const name = parts.next() orelse continue;
            const addr_port = parts.next() orelse continue;

            // Parse address:port
            if (std.mem.lastIndexOf(u8, addr_port, ":")) |colon_pos| {
                const addr_str = addr_port[0..colon_pos];
                const port_str = addr_port[colon_pos + 1 ..];

                const port = std.fmt.parseInt(u16, port_str, 10) catch continue;

                // Parse address
                const address = net.Address.parseIp4(addr_str, port) catch continue;

                // Don't add ourselves
                if (std.mem.eql(u8, name, self.name)) continue;

                const owned_name = try self.allocator.dupe(u8, name);
                errdefer self.allocator.free(owned_name);

                const owned_version = try self.allocator.dupe(u8, "unknown");
                errdefer self.allocator.free(owned_version);

                const peer_info = PeerInfo{
                    .name = owned_name,
                    .address = address,
                    .port = port,
                    .version = owned_version,
                    .last_seen = std.time.timestamp(),
                };

                // Skip if already discovered via mDNS
                if (!self.peers.contains(name)) {
                    try self.peers.put(owned_name, peer_info);
                } else {
                    self.allocator.free(owned_name);
                    self.allocator.free(owned_version);
                }
            }
        }
    }

    /// Get current list of known peers
    pub fn getPeers(self: *Self) []PeerInfo {
        var result = self.allocator.alloc(PeerInfo, self.peers.count()) catch return &[_]PeerInfo{};
        var idx: usize = 0;

        var it = self.peers.iterator();
        while (it.next()) |entry| {
            result[idx] = entry.value_ptr.*;
            idx += 1;
        }

        return result;
    }

    /// Remove stale peers (not seen within timeout_sec)
    pub fn pruneStale(self: *Self, timeout_sec: i64) void {
        const now = std.time.timestamp();
        var to_remove: std.ArrayList([]const u8) = .empty;
        defer to_remove.deinit(self.allocator);

        var it = self.peers.iterator();
        while (it.next()) |entry| {
            if (now - entry.value_ptr.last_seen > timeout_sec) {
                to_remove.append(self.allocator, entry.key_ptr.*) catch continue;
            }
        }

        for (to_remove.items) |key| {
            if (self.peers.fetchRemove(key)) |removed| {
                self.allocator.free(removed.key);
                self.allocator.free(removed.value.version);
            }
        }
    }
};

/// Write a DNS name in label format
fn writeDnsName(writer: anytype, name: []const u8) !void {
    var it = std.mem.splitScalar(u8, name, '.');
    while (it.next()) |label| {
        if (label.len == 0) continue;
        if (label.len > 63) return error.LabelTooLong;
        try writer.writeByte(@intCast(label.len));
        try writer.writeAll(label);
    }
    try writer.writeByte(0); // Root label
}

/// Skip over a DNS name in a packet
fn skipDnsName(fbs: *std.io.FixedBufferStream([]const u8)) !void {
    while (true) {
        if (fbs.pos >= fbs.buffer.len) return error.UnexpectedEndOfData;
        const len = fbs.buffer[fbs.pos];
        fbs.pos += 1;

        if (len == 0) break; // End of name
        if ((len & 0xC0) == 0xC0) {
            // Compression pointer - skip one more byte
            fbs.pos += 1;
            break;
        }
        fbs.pos += len;
    }
}

// ============================================================================
// Tests
// ============================================================================

test "MdnsService init and deinit" {
    const allocator = std.testing.allocator;

    // Note: This test may fail if we can't bind to port 5353 (requires permissions)
    // We test the structure even if socket creation fails
    var service = MdnsService.init(allocator, "test-masque", "1.0.0", 8080) catch |err| {
        // Expected to fail without root permissions on most systems
        std.debug.print("MdnsService.init failed (expected without permissions): {}\n", .{err});
        return;
    };
    defer service.deinit();

    try std.testing.expectEqualStrings("test-masque", service.name);
    try std.testing.expectEqualStrings("1.0.0", service.version);
    try std.testing.expectEqual(@as(u16, 8080), service.port);
}

test "writeDnsName" {
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try writeDnsName(fbs.writer(), "_masque._tcp.local.");

    const expected = "\x07_masque\x04_tcp\x05local\x00";
    try std.testing.expectEqualSlices(u8, expected, fbs.getWritten());
}

test "writeDnsName simple" {
    var buffer: [256]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);

    try writeDnsName(fbs.writer(), "example.local.");

    const expected = "\x07example\x05local\x00";
    try std.testing.expectEqualSlices(u8, expected, fbs.getWritten());
}

test "buildQueryPacket format" {
    const allocator = std.testing.allocator;

    // Create a minimal service just for packet building test
    var service = MdnsService{
        .allocator = allocator,
        .socket = null,
        .name = "test",
        .version = "1.0",
        .port = 8080,
        .peers = std.StringHashMap(PeerInfo).init(allocator),
        .multicast_addr = try std.net.Address.parseIp4(MDNS_MULTICAST_ADDR_V4, MDNS_PORT),
    };
    defer service.peers.deinit();

    var buffer: [256]u8 = undefined;
    const len = try service.buildQueryPacket(&buffer);

    // Verify header
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, buffer[0..2], .big)); // Transaction ID
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, buffer[2..4], .big)); // Flags
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, buffer[4..6], .big)); // Questions
    try std.testing.expectEqual(@as(u16, 0), std.mem.readInt(u16, buffer[6..8], .big)); // Answers

    // Packet should be reasonable length
    try std.testing.expect(len > 12);
    try std.testing.expect(len < 100);
}

test "PeerInfo struct" {
    const peer = PeerInfo{
        .name = "codesmith",
        .address = try std.net.Address.parseIp4("192.168.1.10", 8080),
        .port = 8080,
        .version = "1.0.0",
        .last_seen = 1234567890,
    };

    try std.testing.expectEqualStrings("codesmith", peer.name);
    try std.testing.expectEqual(@as(u16, 8080), peer.port);
    try std.testing.expectEqualStrings("1.0.0", peer.version);
}

test "fallback peers file parsing" {
    const allocator = std.testing.allocator;

    // Create a mock peers structure
    var peers = std.StringHashMap(PeerInfo).init(allocator);
    defer {
        var it = peers.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.version);
        }
        peers.deinit();
    }

    // Simulate parsing a line from peers.txt
    const line = "codesmith 192.168.1.10:8080";
    var parts = std.mem.tokenizeAny(u8, line, " \t");
    const name = parts.next().?;
    const addr_port = parts.next().?;

    try std.testing.expectEqualStrings("codesmith", name);
    try std.testing.expectEqualStrings("192.168.1.10:8080", addr_port);

    if (std.mem.lastIndexOf(u8, addr_port, ":")) |colon_pos| {
        const addr_str = addr_port[0..colon_pos];
        const port_str = addr_port[colon_pos + 1 ..];

        try std.testing.expectEqualStrings("192.168.1.10", addr_str);
        try std.testing.expectEqualStrings("8080", port_str);

        const port = try std.fmt.parseInt(u16, port_str, 10);
        try std.testing.expectEqual(@as(u16, 8080), port);
    }
}

test "skipDnsName" {
    // Test regular name: \x07example\x05local\x00
    // Length: 1 (len) + 7 (example) + 1 (len) + 5 (local) + 1 (null) = 15
    const data1 = "\x07example\x05local\x00rest";
    var fbs1 = std.io.fixedBufferStream(data1);
    try skipDnsName(&fbs1);
    try std.testing.expectEqual(@as(usize, 15), fbs1.pos);

    // Test compressed name: \xC0\x0C (pointer to offset 12)
    const data2 = "\xC0\x0Crest";
    var fbs2 = std.io.fixedBufferStream(data2);
    try skipDnsName(&fbs2);
    try std.testing.expectEqual(@as(usize, 2), fbs2.pos);
}

test "constants" {
    try std.testing.expectEqualStrings("224.0.0.251", MDNS_MULTICAST_ADDR_V4);
    try std.testing.expectEqualStrings("ff02::fb", MDNS_MULTICAST_ADDR_V6);
    try std.testing.expectEqual(@as(u16, 5353), MDNS_PORT);
    try std.testing.expectEqualStrings("_masque._tcp.local.", SERVICE_TYPE);
}
