// YAML-to-Zig compiler for masque definitions
// Reads personas/*.masque.yaml and generates Zig struct literals
//
// This is a simplified YAML parser that handles the masque YAML subset:
// - Key: value pairs
// - Nested objects (indentation-based)
// - Arrays (- item)
// - Multi-line strings (|)
// - Comments (#)

const std = @import("std");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        try printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "generate")) {
        const input_dir = if (args.len >= 3) args[2] else "personas";
        const output_dir = if (args.len >= 4) args[3] else "generated";
        try generateAll(allocator, input_dir, output_dir);
    } else if (std.mem.eql(u8, command, "single")) {
        if (args.len < 3) {
            std.debug.print("Usage: yaml2zig single <input.yaml> [output.zig]\n", .{});
            return;
        }
        const input = args[2];
        const output = if (args.len >= 4) args[3] else null;
        try generateSingle(allocator, input, output);
    } else if (std.mem.eql(u8, command, "help")) {
        try printUsage();
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        try printUsage();
    }
}

fn printUsage() !void {
    const usage =
        \\yaml2zig - YAML to Zig compiler for masques
        \\
        \\Usage: yaml2zig <command> [args]
        \\
        \\Commands:
        \\  generate [input_dir] [output_dir]  Generate all masques (default: personas -> generated)
        \\  single <input.yaml> [output.zig]   Generate single masque
        \\  help                               Show this help
        \\
    ;
    std.debug.print("{s}", .{usage});
}

fn generateAll(allocator: std.mem.Allocator, input_dir: []const u8, output_dir: []const u8) !void {
    // Ensure output directory exists
    std.fs.cwd().makePath(output_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Open input directory
    var dir = std.fs.cwd().openDir(input_dir, .{ .iterate = true }) catch |err| {
        std.debug.print("Failed to open input directory '{s}': {}\n", .{ input_dir, err });
        return err;
    };
    defer dir.close();

    var count: usize = 0;
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".masque.yaml")) continue;

        // Extract masque name from filename
        const name = entry.name[0 .. entry.name.len - ".masque.yaml".len];

        // Build input and output paths
        const input_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ input_dir, entry.name });
        defer allocator.free(input_path);

        const output_path = try std.fmt.allocPrint(allocator, "{s}/{s}.zig", .{ output_dir, name });
        defer allocator.free(output_path);

        std.debug.print("Generating {s} -> {s}\n", .{ input_path, output_path });

        generateSingle(allocator, input_path, output_path) catch |err| {
            std.debug.print("  Failed: {}\n", .{err});
            continue;
        };

        count += 1;
    }

    std.debug.print("\nGenerated {d} masque(s)\n", .{count});
}

fn generateSingle(allocator: std.mem.Allocator, input_path: []const u8, output_path: ?[]const u8) !void {
    // Read input file
    const yaml_content = std.fs.cwd().readFileAlloc(allocator, input_path, 1024 * 1024) catch |err| {
        std.debug.print("Failed to read '{s}': {}\n", .{ input_path, err });
        return err;
    };
    defer allocator.free(yaml_content);

    // Parse YAML
    var parser = YamlParser.init(allocator, yaml_content);
    defer parser.deinit();

    const masque = parser.parseMasque() catch |err| {
        std.debug.print("Failed to parse '{s}': {}\n", .{ input_path, err });
        return err;
    };
    defer masque.deinit(allocator);

    // Generate Zig code (pass yaml_content for source embedding)
    const zig_code = try generateZigCode(allocator, masque, yaml_content);
    defer allocator.free(zig_code);

    // Write output
    if (output_path) |path| {
        const file = try std.fs.cwd().createFile(path, .{});
        defer file.close();
        try file.writeAll(zig_code);
    } else {
        std.debug.print("{s}", .{zig_code});
    }
}

// Masque data structure matching the schema
const Masque = struct {
    name: []const u8,
    index: i64,
    version: []const u8,
    ring: []const u8,
    context: []const u8,
    lens: []const u8,
    intent_allowed: std.ArrayList([]const u8),
    intent_denied: std.ArrayList([]const u8),
    knowledge: std.ArrayList([]const u8),
    vault_role: []const u8,
    ttl: []const u8,
    domain: []const u8,
    language: []const u8,
    stack: []const u8,
    style: []const u8,
    philosophy: []const u8,
    tagline: []const u8,

    fn deinit(self: *const Masque, allocator: std.mem.Allocator) void {
        var allowed = self.intent_allowed;
        allowed.deinit(allocator);
        var denied = self.intent_denied;
        denied.deinit(allocator);
        var knowledge = self.knowledge;
        knowledge.deinit(allocator);
    }
};

// Simple YAML parser for masque files
const YamlParser = struct {
    allocator: std.mem.Allocator,
    content: []const u8,
    pos: usize,
    strings: std.ArrayList([]const u8),

    fn init(allocator: std.mem.Allocator, content: []const u8) YamlParser {
        return .{
            .allocator = allocator,
            .content = content,
            .pos = 0,
            .strings = .empty,
        };
    }

    fn deinit(self: *YamlParser) void {
        for (self.strings.items) |s| {
            self.allocator.free(s);
        }
        self.strings.deinit(self.allocator);
    }

    fn parseMasque(self: *YamlParser) !Masque {
        _ = self.allocator; // We use .empty for ArrayLists
        var masque = Masque{
            .name = "",
            .index = 0,
            .version = "",
            .ring = "guest",
            .context = "",
            .lens = "",
            .intent_allowed = .empty,
            .intent_denied = .empty,
            .knowledge = .empty,
            .vault_role = "",
            .ttl = "session",
            .domain = "",
            .language = "",
            .stack = "",
            .style = "",
            .philosophy = "",
            .tagline = "",
        };

        // Parse line by line
        var lines = std.mem.splitScalar(u8, self.content, '\n');
        var current_section: []const u8 = "";
        var current_subsection: []const u8 = "";
        var in_multiline = false;
        var multiline_buffer: std.ArrayList(u8) = .empty;
        defer multiline_buffer.deinit(self.allocator);
        var multiline_field: []const u8 = "";

        while (lines.next()) |line| {
            // Skip empty lines and comments (unless in multiline)
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (!in_multiline) {
                if (trimmed.len == 0 or trimmed[0] == '#') continue;
            }

            // Check for multiline continuation
            if (in_multiline) {
                // Check if this line starts a new top-level key (no leading space and contains :)
                if (line.len > 0 and line[0] != ' ' and line[0] != '\t') {
                    if (std.mem.indexOf(u8, line, ":")) |_| {
                        // End multiline and process this line
                        in_multiline = false;
                        const multiline_value = try self.allocator.dupe(u8, multiline_buffer.items);
                        try self.strings.append(self.allocator, multiline_value);

                        if (std.mem.eql(u8, multiline_field, "context")) {
                            masque.context = multiline_value;
                        } else if (std.mem.eql(u8, multiline_field, "lens")) {
                            masque.lens = multiline_value;
                        }
                        multiline_buffer.clearRetainingCapacity();
                        // Fall through to process this line
                    } else {
                        // Continue multiline
                        if (multiline_buffer.items.len > 0) {
                            try multiline_buffer.append(self.allocator, '\n');
                        }
                        try multiline_buffer.appendSlice(self.allocator, trimmed);
                        continue;
                    }
                } else {
                    // Continue multiline
                    if (multiline_buffer.items.len > 0) {
                        try multiline_buffer.append(self.allocator, '\n');
                    }
                    // Preserve relative indentation but trim common prefix
                    const content_start = if (line.len >= 2 and (line[0] == ' ' or line[0] == '\t')) blk: {
                        var i: usize = 0;
                        while (i < line.len and (line[i] == ' ' or line[i] == '\t')) : (i += 1) {}
                        break :blk if (i >= 2) @min(i, 2) else 0;
                    } else 0;
                    try multiline_buffer.appendSlice(self.allocator, line[content_start..]);
                    continue;
                }
            }

            // Check indentation level
            const indent = getIndent(line);

            if (indent == 0) {
                // Top-level key
                if (parseKeyValue(trimmed)) |kv| {
                    current_section = kv.key;
                    current_subsection = "";

                    if (std.mem.eql(u8, kv.key, "name")) {
                        masque.name = try self.dupeString(kv.value);
                    } else if (std.mem.eql(u8, kv.key, "index")) {
                        masque.index = std.fmt.parseInt(i64, kv.value, 10) catch 0;
                    } else if (std.mem.eql(u8, kv.key, "version")) {
                        masque.version = try self.dupeString(stripQuotes(kv.value));
                    } else if (std.mem.eql(u8, kv.key, "ring")) {
                        masque.ring = try self.dupeString(kv.value);
                    } else if (std.mem.eql(u8, kv.key, "context")) {
                        if (std.mem.eql(u8, kv.value, "|")) {
                            in_multiline = true;
                            multiline_field = "context";
                        } else {
                            masque.context = try self.dupeString(kv.value);
                        }
                    } else if (std.mem.eql(u8, kv.key, "lens")) {
                        if (std.mem.eql(u8, kv.value, "|")) {
                            in_multiline = true;
                            multiline_field = "lens";
                        } else {
                            masque.lens = try self.dupeString(kv.value);
                        }
                    }
                }
            } else if (indent > 0 and indent < 4) {
                // Second level (inside attributes, intent, access, etc.) - indent 2
                if (parseKeyValue(trimmed)) |kv| {
                    current_subsection = kv.key;

                    if (std.mem.eql(u8, current_section, "attributes")) {
                        if (std.mem.eql(u8, kv.key, "domain")) {
                            masque.domain = try self.dupeString(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "language")) {
                            masque.language = try self.dupeString(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "stack")) {
                            masque.stack = try self.dupeString(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "style")) {
                            masque.style = try self.dupeString(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "philosophy")) {
                            masque.philosophy = try self.dupeString(stripQuotes(kv.value));
                        } else if (std.mem.eql(u8, kv.key, "tagline")) {
                            masque.tagline = try self.dupeString(stripQuotes(kv.value));
                        }
                    } else if (std.mem.eql(u8, current_section, "access")) {
                        if (std.mem.eql(u8, kv.key, "vault_role")) {
                            masque.vault_role = try self.dupeString(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "ttl")) {
                            masque.ttl = try self.dupeString(kv.value);
                        }
                    }
                } else if (trimmed[0] == '-') {
                    // Array item at second level (for knowledge which is a direct array under root)
                    const item = std.mem.trim(u8, trimmed[1..], " \t");
                    if (std.mem.eql(u8, current_section, "knowledge")) {
                        try masque.knowledge.append(self.allocator, try self.dupeString(item));
                    }
                }
            } else {
                // Third level (inside intent.allowed, intent.denied, etc.) - indent >= 4
                if (trimmed[0] == '-') {
                    const item = std.mem.trim(u8, trimmed[1..], " \t");
                    const unquoted = stripQuotes(item);
                    if (std.mem.eql(u8, current_section, "intent")) {
                        if (std.mem.eql(u8, current_subsection, "allowed")) {
                            try masque.intent_allowed.append(self.allocator, try self.dupeString(unquoted));
                        } else if (std.mem.eql(u8, current_subsection, "denied")) {
                            try masque.intent_denied.append(self.allocator, try self.dupeString(unquoted));
                        }
                    }
                }
            }
        }

        // Handle final multiline if still open
        if (in_multiline and multiline_buffer.items.len > 0) {
            const multiline_value = try self.allocator.dupe(u8, multiline_buffer.items);
            try self.strings.append(self.allocator, multiline_value);

            if (std.mem.eql(u8, multiline_field, "context")) {
                masque.context = multiline_value;
            } else if (std.mem.eql(u8, multiline_field, "lens")) {
                masque.lens = multiline_value;
            }
        }

        return masque;
    }

    fn dupeString(self: *YamlParser, s: []const u8) ![]const u8 {
        const duped = try self.allocator.dupe(u8, s);
        try self.strings.append(self.allocator, duped);
        return duped;
    }

    fn getIndent(line: []const u8) usize {
        var indent: usize = 0;
        for (line) |c| {
            if (c == ' ') {
                indent += 1;
            } else if (c == '\t') {
                indent += 2;
            } else {
                break;
            }
        }
        return indent;
    }

    const KeyValue = struct { key: []const u8, value: []const u8 };

    fn parseKeyValue(line: []const u8) ?KeyValue {
        const colon_pos = std.mem.indexOf(u8, line, ":") orelse return null;
        const key = std.mem.trim(u8, line[0..colon_pos], " \t");
        const value = if (colon_pos + 1 < line.len)
            std.mem.trim(u8, line[colon_pos + 1 ..], " \t")
        else
            "";
        return .{ .key = key, .value = value };
    }

    fn stripQuotes(s: []const u8) []const u8 {
        if (s.len >= 2) {
            if ((s[0] == '"' and s[s.len - 1] == '"') or
                (s[0] == '\'' and s[s.len - 1] == '\''))
            {
                return s[1 .. s.len - 1];
            }
        }
        return s;
    }
};

fn generateZigCode(allocator: std.mem.Allocator, masque: Masque, yaml_source: []const u8) ![]const u8 {
    var code: std.ArrayList(u8) = .empty;
    errdefer code.deinit(allocator);
    const writer = code.writer(allocator);

    // Create lowercase name for filename
    var lower_buf: [128]u8 = undefined;
    const lower_name = std.ascii.lowerString(lower_buf[0..masque.name.len], masque.name);

    // Header
    try writer.print(
        \\// Auto-generated masque definition for {s}
        \\// Generated by yaml2zig from personas/{s}.masque.yaml
        \\// DO NOT EDIT - regenerate with: zig build generate
        \\
        \\const interface = @import("interface");
        \\
        \\// Original YAML source embedded for --source command
        \\pub const source_yaml =
    , .{
        masque.name,
        lower_name,
    });

    // Embed the YAML source as a multiline string literal
    try writeMultilineString(writer, yaml_source);
    try writer.writeAll(";\n\n");

    try writer.print(
        \\pub const masque = interface.Masque{{
        \\    .name = "{s}",
        \\    .index = {d},
        \\    .version = "{s}",
        \\    .ring = .{s},
        \\    .context =
    , .{
        escapeString(masque.name),
        masque.index,
        escapeString(masque.version),
        masque.ring,
    });

    // Context (multiline)
    try writeMultilineString(writer, masque.context);
    try writer.writeAll(",\n    .lens =\n");

    // Lens (multiline)
    try writeMultilineString(writer, masque.lens);
    try writer.writeAll(",\n");

    // Intent allowed
    try writer.writeAll("    .intent_allowed = &[_][]const u8{\n");
    for (masque.intent_allowed.items) |pattern| {
        try writer.print("        \"{s}\",\n", .{escapeString(pattern)});
    }
    try writer.writeAll("    },\n");

    // Intent denied
    try writer.writeAll("    .intent_denied = &[_][]const u8{\n");
    for (masque.intent_denied.items) |pattern| {
        try writer.print("        \"{s}\",\n", .{escapeString(pattern)});
    }
    try writer.writeAll("    },\n");

    // Knowledge
    try writer.writeAll("    .knowledge = &[_][]const u8{\n");
    for (masque.knowledge.items) |uri| {
        try writer.print("        \"{s}\",\n", .{escapeString(uri)});
    }
    try writer.writeAll("    },\n");

    // Access
    try writer.print(
        \\    .vault_role = "{s}",
        \\    .ttl = "{s}",
        \\
    , .{ escapeString(masque.vault_role), escapeString(masque.ttl) });

    // Attributes
    try writer.print(
        \\    .domain = "{s}",
        \\    .stack = "{s}",
        \\    .style = "{s}",
        \\    .philosophy = "{s}",
        \\    .tagline = "{s}",
        \\}};
        \\
    , .{
        escapeString(if (masque.domain.len > 0) masque.domain else masque.language),
        escapeString(masque.stack),
        escapeString(masque.style),
        escapeString(masque.philosophy),
        escapeString(masque.tagline),
    });

    return code.toOwnedSlice(allocator);
}

fn writeMultilineString(writer: anytype, s: []const u8) !void {
    if (s.len == 0) {
        try writer.writeAll("        \"\"\n");
        return;
    }

    // Use multiline string literal
    try writer.writeAll("        \\\\\n");
    var lines = std.mem.splitScalar(u8, s, '\n');
    while (lines.next()) |line| {
        try writer.writeAll("        \\\\");
        for (line) |c| {
            switch (c) {
                '\\' => try writer.writeAll("\\\\"),
                '\r' => {},
                else => try writer.writeByte(c),
            }
        }
        try writer.writeAll("\n");
    }
}

fn escapeString(s: []const u8) []const u8 {
    // For simple strings that don't need escaping, return as-is
    // A proper implementation would escape special characters
    return s;
}

test "parse simple masque" {
    const yaml =
        \\name: Test
        \\index: 1
        \\version: "0.1.0"
        \\ring: player
    ;

    var parser = YamlParser.init(std.testing.allocator, yaml);
    defer parser.deinit();

    const masque = try parser.parseMasque();
    defer masque.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("Test", masque.name);
    try std.testing.expectEqual(@as(i64, 1), masque.index);
    try std.testing.expectEqualStrings("0.1.0", masque.version);
    try std.testing.expectEqualStrings("player", masque.ring);
}
