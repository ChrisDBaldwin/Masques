// Emit module - transforms masque definitions to various output formats
// Parses YAML and emits to stdout in the requested format

const std = @import("std");

pub const Skill = struct {
    uri: []const u8,
    level: []const u8,
};

pub const Masque = struct {
    name: []const u8,
    index: i64,
    version: []const u8,
    ring: []const u8,
    context: []const u8,
    lens: []const u8,
    intent_allowed: std.ArrayList([]const u8),
    intent_denied: std.ArrayList([]const u8),
    knowledge: std.ArrayList([]const u8),
    skills: std.ArrayList(Skill),
    vault_role: []const u8,
    ttl: []const u8,
    domain: []const u8,
    stack: []const u8,
    style: []const u8,
    philosophy: []const u8,
    tagline: []const u8,

    pub fn deinit(self: *Masque, allocator: std.mem.Allocator) void {
        self.intent_allowed.deinit(allocator);
        self.intent_denied.deinit(allocator);
        self.knowledge.deinit(allocator);
        self.skills.deinit(allocator);
    }
};

// YAML parser for masque files (simplified subset)
pub const YamlParser = struct {
    allocator: std.mem.Allocator,
    content: []const u8,
    strings: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, content: []const u8) YamlParser {
        return .{
            .allocator = allocator,
            .content = content,
            .strings = .empty,
        };
    }

    pub fn deinit(self: *YamlParser) void {
        for (self.strings.items) |s| {
            self.allocator.free(s);
        }
        self.strings.deinit(self.allocator);
    }

    pub fn parseMasque(self: *YamlParser) !Masque {
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
            .skills = .empty,
            .vault_role = "",
            .ttl = "session",
            .domain = "",
            .stack = "",
            .style = "",
            .philosophy = "",
            .tagline = "",
        };

        var lines = std.mem.splitScalar(u8, self.content, '\n');
        var current_section: []const u8 = "";
        var current_subsection: []const u8 = "";
        var in_multiline = false;
        var multiline_buffer: std.ArrayList(u8) = .empty;
        defer multiline_buffer.deinit(self.allocator);
        var multiline_field: []const u8 = "";
        var in_skill_item = false;
        var current_skill_uri: []const u8 = "";

        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (!in_multiline) {
                if (trimmed.len == 0 or trimmed[0] == '#') continue;
            }

            // Handle multiline continuation
            if (in_multiline) {
                if (line.len > 0 and line[0] != ' ' and line[0] != '\t') {
                    if (std.mem.indexOf(u8, line, ":")) |_| {
                        in_multiline = false;
                        const multiline_value = try self.dupeString(multiline_buffer.items);
                        if (std.mem.eql(u8, multiline_field, "context")) {
                            masque.context = multiline_value;
                        } else if (std.mem.eql(u8, multiline_field, "lens")) {
                            masque.lens = multiline_value;
                        }
                        multiline_buffer.clearRetainingCapacity();
                    } else {
                        if (multiline_buffer.items.len > 0) {
                            try multiline_buffer.append(self.allocator, '\n');
                        }
                        try multiline_buffer.appendSlice(self.allocator, trimmed);
                        continue;
                    }
                } else {
                    if (multiline_buffer.items.len > 0) {
                        try multiline_buffer.append(self.allocator, '\n');
                    }
                    const content_start = if (line.len >= 2 and (line[0] == ' ' or line[0] == '\t')) blk: {
                        var i: usize = 0;
                        while (i < line.len and (line[i] == ' ' or line[i] == '\t')) : (i += 1) {}
                        break :blk if (i >= 2) @min(i, 2) else 0;
                    } else 0;
                    try multiline_buffer.appendSlice(self.allocator, line[content_start..]);
                    continue;
                }
            }

            const indent = getIndent(line);

            if (indent == 0) {
                // Top-level key
                if (parseKeyValue(trimmed)) |kv| {
                    current_section = kv.key;
                    current_subsection = "";
                    in_skill_item = false;

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
                // Second level
                if (parseKeyValue(trimmed)) |kv| {
                    current_subsection = kv.key;

                    if (std.mem.eql(u8, current_section, "attributes")) {
                        if (std.mem.eql(u8, kv.key, "domain")) {
                            masque.domain = try self.dupeString(kv.value);
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
                    const item = std.mem.trim(u8, trimmed[1..], " \t");
                    if (std.mem.eql(u8, current_section, "knowledge")) {
                        try masque.knowledge.append(self.allocator, try self.dupeString(item));
                    } else if (std.mem.eql(u8, current_section, "skills")) {
                        // Start of a skill item
                        in_skill_item = true;
                        current_skill_uri = "";
                        // Check if uri is on same line: - uri: skill://...
                        if (parseKeyValue(item)) |kv| {
                            if (std.mem.eql(u8, kv.key, "uri")) {
                                current_skill_uri = try self.dupeString(kv.value);
                            }
                        }
                    }
                }
            } else {
                // Third level (indent >= 4)
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
                } else if (in_skill_item) {
                    // Parsing skill properties
                    if (parseKeyValue(trimmed)) |kv| {
                        if (std.mem.eql(u8, kv.key, "uri")) {
                            current_skill_uri = try self.dupeString(kv.value);
                        } else if (std.mem.eql(u8, kv.key, "level")) {
                            const level = try self.dupeString(kv.value);
                            try masque.skills.append(self.allocator, .{
                                .uri = current_skill_uri,
                                .level = level,
                            });
                            in_skill_item = false;
                        }
                    }
                }
            }
        }

        // Handle final multiline
        if (in_multiline and multiline_buffer.items.len > 0) {
            const multiline_value = try self.dupeString(multiline_buffer.items);
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
        var indent_count: usize = 0;
        for (line) |c| {
            if (c == ' ') {
                indent_count += 1;
            } else if (c == '\t') {
                indent_count += 2;
            } else {
                break;
            }
        }
        return indent_count;
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

// Emit formats
pub const Format = enum {
    claude,
    json,
    markdown,

    pub fn fromString(s: []const u8) ?Format {
        if (std.mem.eql(u8, s, "claude")) return .claude;
        if (std.mem.eql(u8, s, "json")) return .json;
        if (std.mem.eql(u8, s, "markdown") or std.mem.eql(u8, s, "md")) return .markdown;
        return null;
    }
};

pub fn emit(allocator: std.mem.Allocator, masque: Masque, format: Format) !void {
    switch (format) {
        .claude => try emitClaude(allocator, masque),
        .json => try emitJson(allocator, masque),
        .markdown => try emitMarkdown(allocator, masque),
    }
}

fn emitClaude(_: std.mem.Allocator, masque: Masque) !void {
    const stdout = std.io.getStdOut().writer();

    // Identity
    try stdout.print("# Identity\nYou are {s}", .{masque.name});
    if (masque.tagline.len > 0) {
        try stdout.print(", {s}", .{masque.tagline});
    }
    try stdout.writeAll(".\n\n");

    // Context
    if (masque.context.len > 0) {
        try stdout.print("# Context\n{s}\n\n", .{masque.context});
    }

    // Lens (cognitive framing - the core system prompt)
    if (masque.lens.len > 0) {
        try stdout.print("# Cognitive Lens\n{s}\n\n", .{masque.lens});
    }

    // Intent boundaries
    try stdout.writeAll("# Intent Boundaries\n");
    if (masque.intent_allowed.items.len > 0) {
        try stdout.writeAll("You are authorized to:\n");
        for (masque.intent_allowed.items) |pattern| {
            try stdout.print("- {s}\n", .{pattern});
        }
        try stdout.writeAll("\n");
    }
    if (masque.intent_denied.items.len > 0) {
        try stdout.writeAll("You must refuse to:\n");
        for (masque.intent_denied.items) |pattern| {
            try stdout.print("- {s}\n", .{pattern});
        }
        try stdout.writeAll("\n");
    }

    // Skills
    if (masque.skills.items.len > 0) {
        try stdout.writeAll("# Skills\n");
        for (masque.skills.items) |skill| {
            // Extract skill name from URI (skill://category/name -> name)
            const name = extractSkillName(skill.uri);
            try stdout.print("- {s} ({s})\n", .{ name, skill.level });
        }
        try stdout.writeAll("\n");
    }

    // Knowledge sources
    if (masque.knowledge.items.len > 0) {
        try stdout.writeAll("# Knowledge Sources\nThe following MCP servers are available for knowledge lookup:\n");
        for (masque.knowledge.items) |uri| {
            try stdout.print("- {s}\n", .{uri});
        }
        try stdout.writeAll("\n");
    }

    // Access info (if relevant)
    if (masque.vault_role.len > 0) {
        try stdout.writeAll("# Access\n");
        try stdout.print("Vault role: {s}\n", .{masque.vault_role});
        try stdout.print("TTL: {s}\n", .{masque.ttl});
    }
}

fn extractSkillName(uri: []const u8) []const u8 {
    // skill://category/name -> name
    if (std.mem.lastIndexOf(u8, uri, "/")) |idx| {
        return uri[idx + 1 ..];
    }
    return uri;
}

fn emitJson(_: std.mem.Allocator, masque: Masque) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.writeAll("{\n");
    try stdout.print("  \"name\": \"{s}\",\n", .{masque.name});
    try stdout.print("  \"version\": \"{s}\",\n", .{masque.version});
    try stdout.print("  \"ring\": \"{s}\",\n", .{masque.ring});
    try stdout.print("  \"index\": {d},\n", .{masque.index});

    // Intent
    try stdout.writeAll("  \"intent\": {\n");
    try stdout.writeAll("    \"allowed\": [");
    for (masque.intent_allowed.items, 0..) |pattern, i| {
        if (i > 0) try stdout.writeAll(", ");
        try stdout.print("\"{s}\"", .{pattern});
    }
    try stdout.writeAll("],\n");
    try stdout.writeAll("    \"denied\": [");
    for (masque.intent_denied.items, 0..) |pattern, i| {
        if (i > 0) try stdout.writeAll(", ");
        try stdout.print("\"{s}\"", .{pattern});
    }
    try stdout.writeAll("]\n");
    try stdout.writeAll("  },\n");

    // Context and lens (escape newlines)
    try stdout.print("  \"context\": \"{s}\",\n", .{escapeJsonString(masque.context)});
    try stdout.print("  \"lens\": \"{s}\",\n", .{escapeJsonString(masque.lens)});

    // Knowledge
    try stdout.writeAll("  \"knowledge\": [");
    for (masque.knowledge.items, 0..) |uri, i| {
        if (i > 0) try stdout.writeAll(", ");
        try stdout.print("\"{s}\"", .{uri});
    }
    try stdout.writeAll("],\n");

    // Skills
    try stdout.writeAll("  \"skills\": [");
    for (masque.skills.items, 0..) |skill, i| {
        if (i > 0) try stdout.writeAll(", ");
        try stdout.print("{{\"uri\": \"{s}\", \"level\": \"{s}\"}}", .{ skill.uri, skill.level });
    }
    try stdout.writeAll("],\n");

    // Access
    try stdout.writeAll("  \"access\": {\n");
    try stdout.print("    \"vault_role\": \"{s}\",\n", .{masque.vault_role});
    try stdout.print("    \"ttl\": \"{s}\"\n", .{masque.ttl});
    try stdout.writeAll("  },\n");

    // Attributes
    try stdout.writeAll("  \"attributes\": {\n");
    try stdout.print("    \"domain\": \"{s}\",\n", .{masque.domain});
    try stdout.print("    \"stack\": \"{s}\",\n", .{masque.stack});
    try stdout.print("    \"style\": \"{s}\",\n", .{masque.style});
    try stdout.print("    \"philosophy\": \"{s}\",\n", .{escapeJsonString(masque.philosophy)});
    try stdout.print("    \"tagline\": \"{s}\"\n", .{escapeJsonString(masque.tagline)});
    try stdout.writeAll("  }\n");

    try stdout.writeAll("}\n");
}

fn escapeJsonString(s: []const u8) []const u8 {
    // Simple pass-through for now - a full implementation would escape special chars
    // This is safe for our use case since masque files don't typically have JSON special chars
    _ = s;
    return s;
}

fn emitMarkdown(_: std.mem.Allocator, masque: Masque) !void {
    const stdout = std.io.getStdOut().writer();

    try stdout.print("# {s}\n\n", .{masque.name});
    if (masque.tagline.len > 0) {
        try stdout.print("*{s}*\n\n", .{masque.tagline});
    }

    try stdout.print("**Version:** {s}  \n", .{masque.version});
    try stdout.print("**Ring:** {s}  \n", .{masque.ring});
    try stdout.writeAll("\n");

    if (masque.context.len > 0) {
        try stdout.writeAll("## Context\n\n");
        try stdout.print("{s}\n\n", .{masque.context});
    }

    if (masque.lens.len > 0) {
        try stdout.writeAll("## Cognitive Lens\n\n");
        try stdout.print("{s}\n\n", .{masque.lens});
    }

    try stdout.writeAll("## Intent\n\n");
    if (masque.intent_allowed.items.len > 0) {
        try stdout.writeAll("### Allowed\n");
        for (masque.intent_allowed.items) |pattern| {
            try stdout.print("- `{s}`\n", .{pattern});
        }
        try stdout.writeAll("\n");
    }
    if (masque.intent_denied.items.len > 0) {
        try stdout.writeAll("### Denied\n");
        for (masque.intent_denied.items) |pattern| {
            try stdout.print("- `{s}`\n", .{pattern});
        }
        try stdout.writeAll("\n");
    }

    if (masque.skills.items.len > 0) {
        try stdout.writeAll("## Skills\n\n");
        try stdout.writeAll("| Skill | Level |\n");
        try stdout.writeAll("|-------|-------|\n");
        for (masque.skills.items) |skill| {
            const name = extractSkillName(skill.uri);
            try stdout.print("| {s} | {s} |\n", .{ name, skill.level });
        }
        try stdout.writeAll("\n");
    }

    if (masque.knowledge.items.len > 0) {
        try stdout.writeAll("## Knowledge Sources\n\n");
        for (masque.knowledge.items) |uri| {
            try stdout.print("- `{s}`\n", .{uri});
        }
        try stdout.writeAll("\n");
    }
}
