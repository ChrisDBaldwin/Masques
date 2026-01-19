// JSON output utilities for masque binaries
// All commands output JSON for machine parsing

const std = @import("std");

pub const JsonWriter = struct {
    writer: std.io.AnyWriter,
    depth: usize,
    need_comma: bool,

    pub fn init(writer: std.io.AnyWriter) JsonWriter {
        return .{
            .writer = writer,
            .depth = 0,
            .need_comma = false,
        };
    }

    pub fn beginObject(self: *JsonWriter) !void {
        if (self.need_comma) try self.writer.writeAll(",");
        try self.writer.writeAll("{");
        self.depth += 1;
        self.need_comma = false;
    }

    pub fn endObject(self: *JsonWriter) !void {
        self.depth -= 1;
        try self.writer.writeAll("}");
        self.need_comma = true;
    }

    pub fn beginArray(self: *JsonWriter) !void {
        if (self.need_comma) try self.writer.writeAll(",");
        try self.writer.writeAll("[");
        self.depth += 1;
        self.need_comma = false;
    }

    pub fn endArray(self: *JsonWriter) !void {
        self.depth -= 1;
        try self.writer.writeAll("]");
        self.need_comma = true;
    }

    pub fn key(self: *JsonWriter, name: []const u8) !void {
        if (self.need_comma) try self.writer.writeAll(",");
        try self.writer.writeByte('"');
        try writeEscaped(self.writer, name);
        try self.writer.writeAll("\":");
        self.need_comma = false;
    }

    pub fn stringValue(self: *JsonWriter, value: []const u8) !void {
        if (self.need_comma) try self.writer.writeAll(",");
        try self.writer.writeByte('"');
        try writeEscaped(self.writer, value);
        try self.writer.writeByte('"');
        self.need_comma = true;
    }

    pub fn intValue(self: *JsonWriter, value: i64) !void {
        if (self.need_comma) try self.writer.writeAll(",");
        try self.writer.print("{d}", .{value});
        self.need_comma = true;
    }

    pub fn boolValue(self: *JsonWriter, value: bool) !void {
        if (self.need_comma) try self.writer.writeAll(",");
        try self.writer.writeAll(if (value) "true" else "false");
        self.need_comma = true;
    }

    pub fn nullValue(self: *JsonWriter) !void {
        if (self.need_comma) try self.writer.writeAll(",");
        try self.writer.writeAll("null");
        self.need_comma = true;
    }

    pub fn field(self: *JsonWriter, name: []const u8, value: []const u8) !void {
        try self.key(name);
        try self.stringValue(value);
    }

    pub fn fieldInt(self: *JsonWriter, name: []const u8, value: i64) !void {
        try self.key(name);
        try self.intValue(value);
    }

    pub fn fieldBool(self: *JsonWriter, name: []const u8, value: bool) !void {
        try self.key(name);
        try self.boolValue(value);
    }

    pub fn fieldArray(self: *JsonWriter, name: []const u8, values: []const []const u8) !void {
        try self.key(name);
        try self.beginArray();
        for (values) |v| {
            try self.stringValue(v);
        }
        try self.endArray();
    }
};

fn writeEscaped(writer: std.io.AnyWriter, s: []const u8) !void {
    for (s) |c| {
        switch (c) {
            '"' => try writer.writeAll("\\\""),
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            '\t' => try writer.writeAll("\\t"),
            else => {
                if (c < 0x20) {
                    try writer.print("\\u{x:0>4}", .{c});
                } else {
                    try writer.writeByte(c);
                }
            },
        }
    }
}

// Helper functions for common output patterns

pub fn writeSuccess(writer: std.io.AnyWriter, message: []const u8) !void {
    var json = JsonWriter.init(writer);
    try json.beginObject();
    try json.field("status", "success");
    try json.field("message", message);
    try json.endObject();
    try writer.writeByte('\n');
}

pub fn writeError(writer: std.io.AnyWriter, message: []const u8) !void {
    var json = JsonWriter.init(writer);
    try json.beginObject();
    try json.field("status", "error");
    try json.field("message", message);
    try json.endObject();
    try writer.writeByte('\n');
}

test "json output" {
    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    var json = JsonWriter.init(stream.writer().any());

    try json.beginObject();
    try json.field("name", "test");
    try json.fieldInt("count", 42);
    try json.fieldBool("active", true);
    try json.endObject();

    const result = stream.getWritten();
    try std.testing.expectEqualStrings("{\"name\":\"test\",\"count\":42,\"active\":true}", result);
}

test "json escaping" {
    var buf: [1024]u8 = undefined;
    var stream = std.io.fixedBufferStream(&buf);
    var json = JsonWriter.init(stream.writer().any());

    try json.beginObject();
    try json.field("text", "line1\nline2\ttab\"quote");
    try json.endObject();

    const result = stream.getWritten();
    try std.testing.expectEqualStrings("{\"text\":\"line1\\nline2\\ttab\\\"quote\"}", result);
}
