// Masque binary entry point
// This is the template for all masque binaries. Each binary imports
// its own generated masque definition from masque_def.

const std = @import("std");
const masque_def = @import("masque_def");
const interface = @import("interface");
const output = @import("output");
const session = @import("session");
const mesh_coordinator = @import("mesh_coordinator");

const masque = masque_def.masque;

// Buffered stdout writer for Zig 0.15
const BufferedStdout = struct {
    buffer: std.ArrayList(u8),

    fn init(alloc: std.mem.Allocator) BufferedStdout {
        _ = alloc;
        return .{ .buffer = .empty };
    }

    fn writer(self: *BufferedStdout, allocator: std.mem.Allocator) std.ArrayList(u8).Writer {
        return self.buffer.writer(allocator);
    }

    fn flush(self: *BufferedStdout, allocator: std.mem.Allocator) !void {
        const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };
        try stdout.writeAll(self.buffer.items);
        self.buffer.clearRetainingCapacity();
        _ = allocator;
    }

    fn deinit(self: *BufferedStdout, allocator: std.mem.Allocator) void {
        self.buffer.deinit(allocator);
    }
};

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var buf = BufferedStdout.init(allocator);
    defer buf.deinit(allocator);

    if (args.len < 2) {
        try printUsage(allocator, &buf);
        try buf.flush(allocator);
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "info")) {
        try cmdInfo(allocator, &buf);
    } else if (std.mem.eql(u8, command, "qualify")) {
        if (args.len < 3) {
            try writeError(allocator, &buf, "Usage: qualify <intent>");
            try buf.flush(allocator);
            return;
        }
        try cmdQualify(allocator, &buf, args[2]);
    } else if (std.mem.eql(u8, command, "don")) {
        var intent: []const u8 = "";
        // Parse --intent argument
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.startsWith(u8, args[i], "--intent=")) {
                intent = args[i]["--intent=".len..];
            } else if (std.mem.eql(u8, args[i], "--intent") and i + 1 < args.len) {
                i += 1;
                intent = args[i];
            }
        }
        try cmdDon(allocator, &buf, intent);
    } else if (std.mem.eql(u8, command, "doff")) {
        try cmdDoff(allocator, &buf);
    } else if (std.mem.eql(u8, command, "announce")) {
        try cmdAnnounce(allocator, &buf);
    } else if (std.mem.eql(u8, command, "discover")) {
        try cmdDiscover(allocator, &buf);
    } else if (std.mem.eql(u8, command, "message")) {
        if (args.len < 4) {
            try writeError(allocator, &buf, "Usage: message <peer> <json>");
            try buf.flush(allocator);
            return;
        }
        try cmdMessage(allocator, &buf, args[2], args[3]);
    } else if (std.mem.eql(u8, command, "listen")) {
        try cmdListen(allocator, &buf);
    } else if (std.mem.eql(u8, command, "source") or std.mem.eql(u8, command, "--source")) {
        try cmdSource(allocator, &buf);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help")) {
        try printUsage(allocator, &buf);
    } else {
        try writeError(allocator, &buf, "Unknown command");
        try printUsage(allocator, &buf);
    }

    try buf.flush(allocator);
}

fn writeError(allocator: std.mem.Allocator, buf: *BufferedStdout, message: []const u8) !void {
    var json = output.JsonWriter.init(buf.writer(allocator).any());
    try json.beginObject();
    try json.field("status", "error");
    try json.field("message", message);
    try json.endObject();
    try buf.buffer.append(allocator, '\n');
}

fn printUsage(allocator: std.mem.Allocator, buf: *BufferedStdout) !void {
    const writer = buf.writer(allocator);
    var lower_buf: [64]u8 = undefined;
    const lower_name = std.ascii.lowerString(lower_buf[0..masque.name.len], masque.name);

    try writer.print(
        \\{s} v{s} - Masque Binary
        \\
        \\Usage: {s} <command> [args]
        \\
        \\Commands:
        \\  info              Show masque metadata (name, version, ring, capabilities)
        \\  qualify <intent>  Check if intent is allowed for this masque
        \\  don --intent "..."  Start session, output lens/context
        \\  doff              End session
        \\  source            Print original YAML definition (--source)
        \\  announce          Broadcast presence to mesh
        \\  discover          List known peers
        \\  message <peer> <json>  Send message to peer
        \\  listen            Start message listener
        \\  help              Show this help
        \\
    , .{ masque.name, masque.version, lower_name });
}

fn cmdInfo(allocator: std.mem.Allocator, buf: *BufferedStdout) !void {
    var json = output.JsonWriter.init(buf.writer(allocator).any());

    try json.beginObject();
    try json.field("name", masque.name);
    try json.field("version", masque.version);
    try json.field("ring", masque.ring.toString());
    try json.fieldInt("index", masque.index);
    try json.field("domain", masque.domain);
    try json.field("stack", masque.stack);
    try json.field("philosophy", masque.philosophy);
    try json.field("tagline", masque.tagline);
    try json.fieldArray("intent_allowed", masque.intent_allowed);
    try json.fieldArray("intent_denied", masque.intent_denied);
    try json.key("capabilities");
    try json.beginArray();
    try json.stringValue("info");
    try json.stringValue("qualify");
    try json.stringValue("don");
    try json.stringValue("doff");
    try json.stringValue("announce");
    try json.stringValue("discover");
    try json.stringValue("message");
    try json.stringValue("listen");
    try json.endArray();
    try json.endObject();
    try buf.buffer.append(allocator, '\n');
}

fn cmdQualify(allocator: std.mem.Allocator, buf: *BufferedStdout, intent: []const u8) !void {
    const qualified = masque.qualifyIntent(intent);

    var json = output.JsonWriter.init(buf.writer(allocator).any());
    try json.beginObject();
    try json.field("intent", intent);
    try json.fieldBool("qualified", qualified);
    try json.field("masque", masque.name);
    try json.endObject();
    try buf.buffer.append(allocator, '\n');
}

fn cmdDon(allocator: std.mem.Allocator, buf: *BufferedStdout, intent: []const u8) !void {
    // Check if intent is qualified
    if (intent.len > 0 and !masque.qualifyIntent(intent)) {
        var json = output.JsonWriter.init(buf.writer(allocator).any());
        try json.beginObject();
        try json.field("status", "error");
        try json.field("message", "Intent not qualified for this masque");
        try json.field("intent", intent);
        try json.endObject();
        try buf.buffer.append(allocator, '\n');
        return;
    }

    // Create session
    var session_mgr = session.SessionManager.init(allocator) catch {
        try writeError(allocator, buf, "Failed to initialize session manager");
        return;
    };
    defer session_mgr.deinit();

    var sess = session_mgr.createSession(
        masque.name,
        masque.version,
        intent,
        masque.ring.toString(),
    ) catch {
        try writeError(allocator, buf, "Failed to create session");
        return;
    };
    defer sess.deinit(allocator);

    // Output session info with full lens and context
    var json = output.JsonWriter.init(buf.writer(allocator).any());
    try json.beginObject();
    try json.field("status", "success");
    try json.field("session_id", sess.id);
    try json.field("masque", masque.name);
    try json.field("version", masque.version);
    try json.field("ring", masque.ring.toString());
    try json.field("intent", intent);
    try json.fieldInt("started_at", sess.started_at);
    try json.field("lens", masque.lens);
    try json.field("context", masque.context);
    try json.fieldArray("intent_allowed", masque.intent_allowed);
    try json.fieldArray("intent_denied", masque.intent_denied);
    try json.field("domain", masque.domain);
    try json.field("stack", masque.stack);
    try json.field("philosophy", masque.philosophy);
    try json.field("tagline", masque.tagline);
    try json.endObject();
    try buf.buffer.append(allocator, '\n');
}

fn cmdDoff(allocator: std.mem.Allocator, buf: *BufferedStdout) !void {
    var session_mgr = session.SessionManager.init(allocator) catch {
        try writeError(allocator, buf, "Failed to initialize session manager");
        return;
    };
    defer session_mgr.deinit();

    // Find active session for this masque
    const active_session = session_mgr.getActiveSession(masque.name) catch null;

    if (active_session) |sess| {
        var sess_copy = sess;
        defer sess_copy.deinit(allocator);

        session_mgr.endSession(sess.id) catch {
            try writeError(allocator, buf, "Failed to end session");
            return;
        };

        var json = output.JsonWriter.init(buf.writer(allocator).any());
        try json.beginObject();
        try json.field("status", "success");
        try json.field("message", "Session ended");
        try json.field("session_id", sess.id);
        try json.field("masque", masque.name);
        try json.endObject();
        try buf.buffer.append(allocator, '\n');
    } else {
        var json = output.JsonWriter.init(buf.writer(allocator).any());
        try json.beginObject();
        try json.field("status", "success");
        try json.field("message", "No active session");
        try json.field("masque", masque.name);
        try json.endObject();
        try buf.buffer.append(allocator, '\n');
    }
}

fn cmdSource(_: std.mem.Allocator, _: *BufferedStdout) !void {
    // Output the original YAML source directly to stdout (not buffered)
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll(masque_def.source_yaml);
}

fn cmdAnnounce(allocator: std.mem.Allocator, buf: *BufferedStdout) !void {
    var coord = mesh_coordinator.MeshCoordinator.init(
        allocator,
        masque.name,
        masque.version,
        mesh_coordinator.DEFAULT_PORT,
    ) catch {
        try writeError(allocator, buf, "Failed to initialize mesh coordinator");
        return;
    };
    defer coord.deinit();

    coord.announce() catch |err| {
        var json = output.JsonWriter.init(buf.writer(allocator).any());
        try json.beginObject();
        try json.field("status", "error");
        if (err == error.MdnsNotAvailable) {
            try json.field("message", "mDNS not available (requires network permissions)");
        } else {
            try json.field("message", "Failed to announce presence");
        }
        try json.field("masque", masque.name);
        try json.endObject();
        try buf.buffer.append(allocator, '\n');
        return;
    };

    var json = output.JsonWriter.init(buf.writer(allocator).any());
    try json.beginObject();
    try json.field("status", "success");
    try json.field("message", "Announced presence");
    try json.field("masque", masque.name);
    try json.field("service", "_masques._tcp.local.");
    try json.fieldInt("port", mesh_coordinator.DEFAULT_PORT);
    try json.endObject();
    try buf.buffer.append(allocator, '\n');
}

fn cmdDiscover(allocator: std.mem.Allocator, buf: *BufferedStdout) !void {
    var coord = mesh_coordinator.MeshCoordinator.init(
        allocator,
        masque.name,
        masque.version,
        mesh_coordinator.DEFAULT_PORT,
    ) catch {
        try writeError(allocator, buf, "Failed to initialize mesh coordinator");
        return;
    };
    defer coord.deinit();

    const peers = coord.discover(5000) catch |err| {
        var json = output.JsonWriter.init(buf.writer(allocator).any());
        try json.beginObject();
        if (err == error.MdnsNotAvailable) {
            try json.field("status", "warning");
            try json.field("message", "mDNS not available, no peers discovered");
        } else {
            try json.field("status", "error");
            try json.field("message", "Failed to discover peers");
        }
        try json.key("peers");
        try json.beginArray();
        try json.endArray();
        try json.endObject();
        try buf.buffer.append(allocator, '\n');
        return;
    };
    defer allocator.free(peers);

    var json = output.JsonWriter.init(buf.writer(allocator).any());
    try json.beginObject();
    try json.field("status", "success");
    try json.fieldInt("count", @intCast(peers.len));
    try json.key("peers");
    try json.beginArray();
    for (peers) |peer| {
        try json.beginObject();
        try json.field("name", peer.name);
        // Format address as string
        var addr_buf: [64]u8 = undefined;
        const addr_str = formatAddress(peer.address, &addr_buf) catch "unknown";
        try json.field("address", addr_str);
        try json.fieldInt("port", peer.port);
        try json.field("version", peer.version);
        try json.fieldInt("last_seen", peer.last_seen);
        try json.endObject();
    }
    try json.endArray();
    try json.endObject();
    try buf.buffer.append(allocator, '\n');
}

fn formatAddress(address: std.net.Address, buf: []u8) ![]const u8 {
    const bytes = @as(*const [4]u8, @ptrCast(&address.in.sa.addr));
    return std.fmt.bufPrint(buf, "{d}.{d}.{d}.{d}", .{
        bytes[0],
        bytes[1],
        bytes[2],
        bytes[3],
    });
}

fn cmdMessage(allocator: std.mem.Allocator, buf: *BufferedStdout, peer: []const u8, message_json: []const u8) !void {
    var coord = mesh_coordinator.MeshCoordinator.init(
        allocator,
        masque.name,
        masque.version,
        mesh_coordinator.DEFAULT_PORT,
    ) catch {
        try writeError(allocator, buf, "Failed to initialize mesh coordinator");
        return;
    };
    defer coord.deinit();

    // First discover peers to find the target
    _ = coord.discover(2000) catch {};

    // Create the message
    var msg_id_buf: [64]u8 = undefined;
    const timestamp = std.time.timestamp();

    // Generate a simple message ID using timestamp and simple counter
    const msg_id = std.fmt.bufPrint(&msg_id_buf, "{s}-{d}", .{
        masque.name,
        timestamp,
    }) catch "unknown-id";

    const msg = mesh_coordinator.Message{
        .msg_type = .task,
        .from = masque.name,
        .to = peer,
        .id = msg_id,
        .payload = message_json,
        .timestamp = timestamp,
    };

    coord.sendMessage(peer, &msg) catch |err| {
        var json = output.JsonWriter.init(buf.writer(allocator).any());
        try json.beginObject();
        try json.field("status", "error");
        if (err == error.PeerNotFound) {
            try json.field("message", "Peer not found");
        } else {
            try json.field("message", "Failed to send message");
        }
        try json.field("to", peer);
        try json.field("from", masque.name);
        try json.endObject();
        try buf.buffer.append(allocator, '\n');
        return;
    };

    var json = output.JsonWriter.init(buf.writer(allocator).any());
    try json.beginObject();
    try json.field("status", "success");
    try json.field("message", "Message sent");
    try json.field("id", msg_id);
    try json.field("to", peer);
    try json.field("from", masque.name);
    try json.endObject();
    try buf.buffer.append(allocator, '\n');
}

fn cmdListen(allocator: std.mem.Allocator, buf: *BufferedStdout) !void {
    var coord = mesh_coordinator.MeshCoordinator.init(
        allocator,
        masque.name,
        masque.version,
        mesh_coordinator.DEFAULT_PORT,
    ) catch {
        try writeError(allocator, buf, "Failed to initialize mesh coordinator");
        return;
    };
    defer coord.deinit();

    // Start the listener
    coord.startListener() catch |err| {
        var json = output.JsonWriter.init(buf.writer(allocator).any());
        try json.beginObject();
        try json.field("status", "error");
        if (err == error.AddressInUse) {
            try json.field("message", "Port already in use");
        } else {
            try json.field("message", "Failed to start listener");
        }
        try json.field("masque", masque.name);
        try json.fieldInt("port", mesh_coordinator.DEFAULT_PORT);
        try json.endObject();
        try buf.buffer.append(allocator, '\n');
        return;
    };

    // Also announce our presence
    coord.announce() catch {};

    // Output listening status
    var json = output.JsonWriter.init(buf.writer(allocator).any());
    try json.beginObject();
    try json.field("status", "listening");
    try json.field("masque", masque.name);
    try json.fieldInt("port", mesh_coordinator.DEFAULT_PORT);
    try json.field("service", "_masques._tcp.local.");
    try json.endObject();
    try buf.buffer.append(allocator, '\n');
    try buf.flush(allocator);

    const stdout = std.fs.File{ .handle = std.posix.STDOUT_FILENO };

    // Listen loop - accept and handle messages
    while (coord.running) {
        if (coord.acceptOne()) |maybe_msg| {
            if (maybe_msg) |msg_val| {
                var msg = msg_val;
                defer msg.deinit(allocator);

                // Output received message as JSON
                var msg_json = output.JsonWriter.init(buf.writer(allocator).any());
                try msg_json.beginObject();
                try msg_json.field("event", "message_received");
                try msg_json.field("type", msg.msg_type.toString());
                try msg_json.field("from", msg.from);
                if (msg.to) |to| {
                    try msg_json.field("to", to);
                }
                try msg_json.field("id", msg.id);
                try msg_json.fieldInt("timestamp", msg.timestamp);
                // Include raw payload
                try msg_json.key("payload");
                if (msg.payload.len > 0) {
                    try buf.buffer.appendSlice(allocator, msg.payload);
                    msg_json.need_comma = true;
                } else {
                    try msg_json.nullValue();
                }
                try msg_json.endObject();
                try buf.buffer.append(allocator, '\n');
                try buf.flush(allocator);
            }
        } else |_| {
            // Error accepting, continue
        }

        // Periodic health check
        coord.healthCheck();

        // Small sleep to avoid busy-waiting
        std.Thread.sleep(100 * std.time.ns_per_ms);
    }

    // Output shutdown message
    var shutdown_json = output.JsonWriter.init(buf.writer(allocator).any());
    try shutdown_json.beginObject();
    try shutdown_json.field("status", "stopped");
    try shutdown_json.field("masque", masque.name);
    try shutdown_json.endObject();
    try buf.buffer.append(allocator, '\n');
    try stdout.writeAll(buf.buffer.items);
}
