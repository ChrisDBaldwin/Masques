// Wire protocol for masque peer communication
// Frame format: [4 bytes big-endian length][JSON payload]
// Max message size: 1MB

const std = @import("std");

pub const max_message_size: usize = 1024 * 1024; // 1MB

pub const MessageType = enum {
    ping,
    pong,
    announce,
    task,
    result,
    proposal,
    vote,

    pub fn toString(self: MessageType) []const u8 {
        return switch (self) {
            .ping => "ping",
            .pong => "pong",
            .announce => "announce",
            .task => "task",
            .result => "result",
            .proposal => "proposal",
            .vote => "vote",
        };
    }

    pub fn fromString(s: []const u8) ?MessageType {
        const map = std.StaticStringMap(MessageType).initComptime(.{
            .{ "ping", .ping },
            .{ "pong", .pong },
            .{ "announce", .announce },
            .{ "task", .task },
            .{ "result", .result },
            .{ "proposal", .proposal },
            .{ "vote", .vote },
        });
        return map.get(s);
    }
};

pub const Message = struct {
    msg_type: MessageType,
    from: []const u8,
    to: ?[]const u8, // null for broadcast
    id: []const u8,
    payload: []const u8, // JSON payload
    timestamp: i64,

    /// Serialize message to JSON bytes
    pub fn serialize(self: *const Message, allocator: std.mem.Allocator) ![]u8 {
        var buf: std.ArrayList(u8) = .empty;
        errdefer buf.deinit(allocator);

        const writer = buf.writer(allocator);

        try writer.writeAll("{\"type\":\"");
        try writer.writeAll(self.msg_type.toString());
        try writer.writeAll("\",\"from\":\"");
        try writeJsonEscaped(writer, self.from);
        try writer.writeAll("\",");

        if (self.to) |to| {
            try writer.writeAll("\"to\":\"");
            try writeJsonEscaped(writer, to);
            try writer.writeAll("\",");
        }

        try writer.writeAll("\"id\":\"");
        try writeJsonEscaped(writer, self.id);
        try writer.writeAll("\",\"payload\":");

        // Payload is already JSON, write directly
        if (self.payload.len > 0) {
            try writer.writeAll(self.payload);
        } else {
            try writer.writeAll("null");
        }

        try writer.writeAll(",\"timestamp\":");
        try std.fmt.format(writer, "{d}", .{self.timestamp});
        try writer.writeAll("}");

        return buf.toOwnedSlice(allocator);
    }

    /// Deserialize message from JSON bytes
    pub fn deserialize(allocator: std.mem.Allocator, data: []const u8) !Message {
        // Validate it's valid JSON and extract fields
        const parsed = std.json.parseFromSlice(std.json.Value, allocator, data, .{}) catch {
            return error.InvalidJson;
        };
        defer parsed.deinit();

        const root = parsed.value;
        if (root != .object) return error.InvalidMessageFormat;

        const obj = root.object;

        // Required fields
        const type_str = obj.get("type") orelse return error.MissingField;
        if (type_str != .string) return error.InvalidFieldType;
        const msg_type = MessageType.fromString(type_str.string) orelse return error.InvalidMessageType;

        const from_val = obj.get("from") orelse return error.MissingField;
        if (from_val != .string) return error.InvalidFieldType;
        const from = try allocator.dupe(u8, from_val.string);
        errdefer allocator.free(from);

        const id_val = obj.get("id") orelse return error.MissingField;
        if (id_val != .string) return error.InvalidFieldType;
        const id = try allocator.dupe(u8, id_val.string);
        errdefer allocator.free(id);

        const ts_val = obj.get("timestamp") orelse return error.MissingField;
        const timestamp: i64 = switch (ts_val) {
            .integer => ts_val.integer,
            .float => @intFromFloat(ts_val.float),
            else => return error.InvalidFieldType,
        };

        // Optional "to" field
        var to: ?[]const u8 = null;
        if (obj.get("to")) |to_val| {
            if (to_val == .string) {
                to = try allocator.dupe(u8, to_val.string);
            } else if (to_val != .null) {
                return error.InvalidFieldType;
            }
        }
        errdefer if (to) |t| allocator.free(t);

        // Payload - serialize back to JSON string
        var payload: []const u8 = "";
        if (obj.get("payload")) |payload_val| {
            if (payload_val != .null) {
                payload = try stringifyJson(allocator, payload_val);
            }
        }

        return Message{
            .msg_type = msg_type,
            .from = from,
            .to = to,
            .id = id,
            .payload = payload,
            .timestamp = timestamp,
        };
    }

    /// Free allocated memory
    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        allocator.free(self.from);
        if (self.to) |to| allocator.free(to);
        allocator.free(self.id);
        if (self.payload.len > 0) allocator.free(self.payload);
    }

    /// Validate message has required fields with valid values
    pub fn validate(self: *const Message) !void {
        if (self.from.len == 0) return error.EmptyFrom;
        if (self.id.len == 0) return error.EmptyId;
        if (self.timestamp <= 0) return error.InvalidTimestamp;

        // Validate payload is valid JSON if present
        if (self.payload.len > 0) {
            var parsed = std.json.parseFromSlice(std.json.Value, std.heap.page_allocator, self.payload, .{}) catch {
                return error.InvalidPayloadJson;
            };
            parsed.deinit();
        }
    }
};

pub const Frame = struct {
    /// Encode a message into a framed byte sequence
    /// Returns: [4 bytes big-endian length][JSON payload]
    pub fn encode(allocator: std.mem.Allocator, message: *const Message) ![]u8 {
        const json_data = try message.serialize(allocator);
        defer allocator.free(json_data);

        if (json_data.len > max_message_size) {
            return error.MessageTooLarge;
        }

        const frame = try allocator.alloc(u8, 4 + json_data.len);
        errdefer allocator.free(frame);

        // Write length as big-endian u32
        const len: u32 = @intCast(json_data.len);
        frame[0] = @intCast((len >> 24) & 0xFF);
        frame[1] = @intCast((len >> 16) & 0xFF);
        frame[2] = @intCast((len >> 8) & 0xFF);
        frame[3] = @intCast(len & 0xFF);

        // Copy JSON payload
        @memcpy(frame[4..], json_data);

        return frame;
    }

    /// Decode a framed byte sequence into a message
    pub fn decode(allocator: std.mem.Allocator, data: []const u8) !Message {
        if (data.len < 4) return error.FrameTooShort;

        // Read length from big-endian u32
        const len: u32 = (@as(u32, data[0]) << 24) |
            (@as(u32, data[1]) << 16) |
            (@as(u32, data[2]) << 8) |
            @as(u32, data[3]);

        if (len > max_message_size) return error.MessageTooLarge;
        if (data.len < 4 + len) return error.IncompleteFrame;

        const json_data = data[4 .. 4 + len];
        return Message.deserialize(allocator, json_data);
    }

    /// Read a complete frame from a reader
    pub fn readFrame(reader: anytype, allocator: std.mem.Allocator, max_size: usize) ![]u8 {
        // Read 4-byte length header
        var len_buf: [4]u8 = undefined;
        var total_read: usize = 0;
        while (total_read < 4) {
            const bytes = try reader.read(len_buf[total_read..]);
            if (bytes == 0) return error.UnexpectedEof;
            total_read += bytes;
        }

        // Parse big-endian length
        const len: u32 = (@as(u32, len_buf[0]) << 24) |
            (@as(u32, len_buf[1]) << 16) |
            (@as(u32, len_buf[2]) << 8) |
            @as(u32, len_buf[3]);

        const effective_max = @min(max_size, max_message_size);
        if (len > effective_max) return error.MessageTooLarge;

        // Read payload
        const payload = try allocator.alloc(u8, len);
        errdefer allocator.free(payload);

        var payload_read: usize = 0;
        while (payload_read < len) {
            const bytes = try reader.read(payload[payload_read..]);
            if (bytes == 0) {
                allocator.free(payload);
                return error.UnexpectedEof;
            }
            payload_read += bytes;
        }

        return payload;
    }

    /// Write a frame to a writer
    pub fn writeFrame(writer: anytype, data: []const u8) !void {
        if (data.len > max_message_size) return error.MessageTooLarge;

        // Write length as big-endian u32
        const len: u32 = @intCast(data.len);
        var len_buf: [4]u8 = undefined;
        len_buf[0] = @intCast((len >> 24) & 0xFF);
        len_buf[1] = @intCast((len >> 16) & 0xFF);
        len_buf[2] = @intCast((len >> 8) & 0xFF);
        len_buf[3] = @intCast(len & 0xFF);

        try writer.writeAll(&len_buf);
        try writer.writeAll(data);
    }
};

// Helper functions

fn writeJsonEscaped(writer: anytype, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try std.fmt.format(writer, "\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

fn stringifyJson(allocator: std.mem.Allocator, value: std.json.Value) ![]u8 {
    var out: std.io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    var write_stream: std.json.Stringify = .{ .writer = &out.writer };
    try write_stream.write(value);
    // Move ownership to caller
    const result = out.written();
    const owned = try allocator.dupe(u8, result);
    out.deinit();
    return owned;
}

// ============================================================================
// Tests
// ============================================================================

test "MessageType.toString" {
    try std.testing.expectEqualStrings("ping", MessageType.ping.toString());
    try std.testing.expectEqualStrings("pong", MessageType.pong.toString());
    try std.testing.expectEqualStrings("announce", MessageType.announce.toString());
    try std.testing.expectEqualStrings("task", MessageType.task.toString());
    try std.testing.expectEqualStrings("result", MessageType.result.toString());
    try std.testing.expectEqualStrings("proposal", MessageType.proposal.toString());
    try std.testing.expectEqualStrings("vote", MessageType.vote.toString());
}

test "MessageType.fromString" {
    try std.testing.expectEqual(MessageType.ping, MessageType.fromString("ping").?);
    try std.testing.expectEqual(MessageType.pong, MessageType.fromString("pong").?);
    try std.testing.expectEqual(MessageType.announce, MessageType.fromString("announce").?);
    try std.testing.expectEqual(MessageType.task, MessageType.fromString("task").?);
    try std.testing.expectEqual(MessageType.result, MessageType.fromString("result").?);
    try std.testing.expectEqual(MessageType.proposal, MessageType.fromString("proposal").?);
    try std.testing.expectEqual(MessageType.vote, MessageType.fromString("vote").?);
    try std.testing.expectEqual(@as(?MessageType, null), MessageType.fromString("invalid"));
}

test "Message.serialize basic" {
    const allocator = std.testing.allocator;

    const msg = Message{
        .msg_type = .ping,
        .from = "codesmith",
        .to = null,
        .id = "msg-001",
        .payload = "",
        .timestamp = 1234567890,
    };

    const json = try msg.serialize(allocator);
    defer allocator.free(json);

    // Verify it contains expected fields
    try std.testing.expect(std.mem.indexOf(u8, json, "\"type\":\"ping\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"from\":\"codesmith\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"msg-001\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"timestamp\":1234567890") != null);
}

test "Message.serialize with to field" {
    const allocator = std.testing.allocator;

    const msg = Message{
        .msg_type = .task,
        .from = "codesmith",
        .to = "chartwright",
        .id = "msg-002",
        .payload = "{\"action\":\"review\",\"file\":\"main.zig\"}",
        .timestamp = 1234567890,
    };

    const json = try msg.serialize(allocator);
    defer allocator.free(json);

    try std.testing.expect(std.mem.indexOf(u8, json, "\"to\":\"chartwright\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"action\":\"review\"") != null);
}

test "Message.deserialize basic" {
    const allocator = std.testing.allocator;

    const json = "{\"type\":\"ping\",\"from\":\"codesmith\",\"id\":\"msg-001\",\"payload\":null,\"timestamp\":1234567890}";

    var msg = try Message.deserialize(allocator, json);
    defer msg.deinit(allocator);

    try std.testing.expectEqual(MessageType.ping, msg.msg_type);
    try std.testing.expectEqualStrings("codesmith", msg.from);
    try std.testing.expectEqualStrings("msg-001", msg.id);
    try std.testing.expectEqual(@as(i64, 1234567890), msg.timestamp);
    try std.testing.expectEqual(@as(?[]const u8, null), msg.to);
}

test "Message.deserialize with to and payload" {
    const allocator = std.testing.allocator;

    const json = "{\"type\":\"task\",\"from\":\"codesmith\",\"to\":\"chartwright\",\"id\":\"msg-002\",\"payload\":{\"action\":\"review\"},\"timestamp\":1234567890}";

    var msg = try Message.deserialize(allocator, json);
    defer msg.deinit(allocator);

    try std.testing.expectEqual(MessageType.task, msg.msg_type);
    try std.testing.expectEqualStrings("codesmith", msg.from);
    try std.testing.expectEqualStrings("chartwright", msg.to.?);
    try std.testing.expectEqualStrings("msg-002", msg.id);
    try std.testing.expect(std.mem.indexOf(u8, msg.payload, "review") != null);
}

test "Message.deserialize missing required field" {
    const allocator = std.testing.allocator;

    // Missing "from" field
    const json = "{\"type\":\"ping\",\"id\":\"msg-001\",\"timestamp\":1234567890}";

    const result = Message.deserialize(allocator, json);
    try std.testing.expectError(error.MissingField, result);
}

test "Message.deserialize invalid type" {
    const allocator = std.testing.allocator;

    const json = "{\"type\":\"invalid\",\"from\":\"codesmith\",\"id\":\"msg-001\",\"timestamp\":1234567890}";

    const result = Message.deserialize(allocator, json);
    try std.testing.expectError(error.InvalidMessageType, result);
}

test "Message.validate" {
    const valid_msg = Message{
        .msg_type = .ping,
        .from = "codesmith",
        .to = null,
        .id = "msg-001",
        .payload = "{\"key\":\"value\"}",
        .timestamp = 1234567890,
    };

    try valid_msg.validate();

    const empty_from = Message{
        .msg_type = .ping,
        .from = "",
        .to = null,
        .id = "msg-001",
        .payload = "",
        .timestamp = 1234567890,
    };

    try std.testing.expectError(error.EmptyFrom, empty_from.validate());

    const empty_id = Message{
        .msg_type = .ping,
        .from = "codesmith",
        .to = null,
        .id = "",
        .payload = "",
        .timestamp = 1234567890,
    };

    try std.testing.expectError(error.EmptyId, empty_id.validate());
}

test "Frame.encode and decode roundtrip" {
    const allocator = std.testing.allocator;

    const original = Message{
        .msg_type = .task,
        .from = "codesmith",
        .to = "chartwright",
        .id = "msg-123",
        .payload = "{\"action\":\"build\"}",
        .timestamp = 1234567890,
    };

    const frame = try Frame.encode(allocator, &original);
    defer allocator.free(frame);

    // Verify frame structure
    try std.testing.expect(frame.len >= 4);

    // Decode the frame
    var decoded = try Frame.decode(allocator, frame);
    defer decoded.deinit(allocator);

    try std.testing.expectEqual(original.msg_type, decoded.msg_type);
    try std.testing.expectEqualStrings(original.from, decoded.from);
    try std.testing.expectEqualStrings(original.to.?, decoded.to.?);
    try std.testing.expectEqualStrings(original.id, decoded.id);
    try std.testing.expectEqual(original.timestamp, decoded.timestamp);
}

test "Frame.encode length bytes" {
    const allocator = std.testing.allocator;

    const msg = Message{
        .msg_type = .ping,
        .from = "a",
        .to = null,
        .id = "b",
        .payload = "",
        .timestamp = 1,
    };

    const frame = try Frame.encode(allocator, &msg);
    defer allocator.free(frame);

    // Read back the length
    const len: u32 = (@as(u32, frame[0]) << 24) |
        (@as(u32, frame[1]) << 16) |
        (@as(u32, frame[2]) << 8) |
        @as(u32, frame[3]);

    try std.testing.expectEqual(@as(u32, @intCast(frame.len - 4)), len);
}

test "Frame.decode incomplete frame" {
    const allocator = std.testing.allocator;

    // Frame claiming 100 bytes but only having 10
    const data = [_]u8{ 0, 0, 0, 100, 'h', 'e', 'l', 'l', 'o', 0 };

    const result = Frame.decode(allocator, &data);
    try std.testing.expectError(error.IncompleteFrame, result);
}

test "Frame.decode frame too short" {
    const allocator = std.testing.allocator;

    const data = [_]u8{ 0, 0, 1 }; // Only 3 bytes

    const result = Frame.decode(allocator, &data);
    try std.testing.expectError(error.FrameTooShort, result);
}

test "Frame.readFrame and writeFrame" {
    const allocator = std.testing.allocator;

    const test_data = "{\"type\":\"ping\",\"from\":\"test\",\"id\":\"1\",\"timestamp\":123}";

    // Write to a buffer
    var write_buf: [1024]u8 = undefined;
    var write_stream = std.io.fixedBufferStream(&write_buf);
    try Frame.writeFrame(write_stream.writer(), test_data);

    // Read it back
    write_stream.pos = 0;
    const read_data = try Frame.readFrame(write_stream.reader(), allocator, max_message_size);
    defer allocator.free(read_data);

    try std.testing.expectEqualStrings(test_data, read_data);
}

test "Frame.readFrame too large" {
    var buf: [8]u8 = undefined;
    // Write a length of max_message_size + 1
    const too_large: u32 = max_message_size + 1;
    buf[0] = @intCast((too_large >> 24) & 0xFF);
    buf[1] = @intCast((too_large >> 16) & 0xFF);
    buf[2] = @intCast((too_large >> 8) & 0xFF);
    buf[3] = @intCast(too_large & 0xFF);

    var stream = std.io.fixedBufferStream(&buf);
    const result = Frame.readFrame(stream.reader(), std.testing.allocator, max_message_size);
    try std.testing.expectError(error.MessageTooLarge, result);
}

test "writeJsonEscaped" {
    const allocator = std.testing.allocator;
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    try writeJsonEscaped(buf.writer(allocator), "hello\"world\\test\nline");

    try std.testing.expectEqualStrings("hello\\\"world\\\\test\\nline", buf.items);
}

test "serialize deserialize roundtrip preserves data" {
    const allocator = std.testing.allocator;

    const original = Message{
        .msg_type = .proposal,
        .from = "coordinator",
        .to = "voter-1",
        .id = "prop-abc-123",
        .payload = "{\"action\":\"merge\",\"branch\":\"feature/test\",\"votes_needed\":3}",
        .timestamp = 1704067200,
    };

    const json = try original.serialize(allocator);
    defer allocator.free(json);

    var restored = try Message.deserialize(allocator, json);
    defer restored.deinit(allocator);

    try std.testing.expectEqual(original.msg_type, restored.msg_type);
    try std.testing.expectEqualStrings(original.from, restored.from);
    try std.testing.expectEqualStrings(original.to.?, restored.to.?);
    try std.testing.expectEqualStrings(original.id, restored.id);
    try std.testing.expectEqual(original.timestamp, restored.timestamp);

    // Payload should parse to equivalent JSON
    const orig_parsed = try std.json.parseFromSlice(std.json.Value, allocator, original.payload, .{});
    defer orig_parsed.deinit();
    const rest_parsed = try std.json.parseFromSlice(std.json.Value, allocator, restored.payload, .{});
    defer rest_parsed.deinit();

    // Check key values
    try std.testing.expectEqualStrings("merge", orig_parsed.value.object.get("action").?.string);
    try std.testing.expectEqualStrings("merge", rest_parsed.value.object.get("action").?.string);
}
