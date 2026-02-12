const std = @import("std");
const Yaml = @import("yaml").Yaml;

pub const Source = enum {
    shared,
    private,

    pub fn label(self: Source) []const u8 {
        return switch (self) {
            .shared => "shared",
            .private => "private",
        };
    }
};

pub const Category = enum {
    all,
    executive,
    cognitive,
    specialist,
    art,
    meta,

    pub fn label(self: Category) []const u8 {
        return switch (self) {
            .all => "All",
            .executive => "Executive",
            .cognitive => "Cognitive",
            .specialist => "Specialist",
            .art => "Art",
            .meta => "Meta",
        };
    }
};

pub const Masque = struct {
    name: []const u8,
    version: []const u8,
    domain: []const u8,
    tagline: []const u8,
    style: []const u8,
    philosophy: []const u8,
    complement: []const u8,
    shadow: []const u8,
    lens_summary: []const u8,
    lens: []const u8,
    context: []const u8,
    category: Category,
    abbrev: [2]u8,
    detail_loaded: bool,
    source: Source,
    detail_dir: []const u8,
};

pub fn categorize(domain: []const u8) Category {
    const exec_domains = [_][]const u8{
        "corporate-governance",  "executive-leadership", "revenue",
        "finance",              "legal-compliance",     "engineering-leadership",
        "marketing-growth",     "operations",           "people-culture",
        "product-management",   "technology-strategy",
    };
    for (exec_domains) |d| {
        if (std.mem.eql(u8, domain, d)) return .executive;
    }

    const cog_domains = [_][]const u8{
        "cybernetic-systems",       "leverage-intervention",
        "historical-pattern-analysis", "structural-abstraction",
        "cross-domain-synthesis",   "applied-competence",
    };
    for (cog_domains) |d| {
        if (std.mem.eql(u8, domain, d)) return .cognitive;
    }

    const art_domains = [_][]const u8{
        "terminal-interfaces", "web-frontend",     "ios-design",
        "android-design",      "3d-art",           "high-art",
        "low-art",             "creative-encouragement",
    };
    for (art_domains) |d| {
        if (std.mem.eql(u8, domain, d)) return .art;
    }

    const meta_domains = [_][]const u8{
        "masque-creation", "masque-evaluation",
    };
    for (meta_domains) |d| {
        if (std.mem.eql(u8, domain, d)) return .meta;
    }

    return .specialist;
}

pub fn abbreviate(name: []const u8) [2]u8 {
    var result = [2]u8{ ' ', ' ' };
    if (name.len == 0) return result;

    result[0] = std.ascii.toUpper(name[0]);
    var i: usize = 1;
    while (i < name.len) : (i += 1) {
        const c = std.ascii.toLower(name[i]);
        if (c != 'a' and c != 'e' and c != 'i' and c != 'o' and c != 'u') {
            result[1] = std.ascii.toLower(name[i]);
            return result;
        }
    }
    if (name.len > 1) {
        result[1] = std.ascii.toLower(name[1]);
    }
    return result;
}

/// Complement pairs — SPECULATIVE. These are hand-curated guesses about
/// which masques work well together. They affect TUI display (synergy
/// indicators) but have no data backing them yet. Treat as hypotheses
/// to be validated through observed team performance.
const complement_pairs = [_][2][]const u8{
    .{ "Steersman", "Fulcrum" },
    .{ "Crucible", "Weaver" },
    .{ "Palimpsest", "Parallax" },
    .{ "Mirror", "Witness" },
    .{ "Codesmith", "Chartwright" },
    .{ "Firekeeper", "Codesmith" },
    .{ "Gilder", "Stencil" },
    .{ "Glyph", "Loom" },
    .{ "Orchard", "Kiln" },
    .{ "Lathe", "Easel" },
};

pub fn findComplement(name: []const u8) ?[]const u8 {
    for (complement_pairs) |pair| {
        if (std.mem.eql(u8, name, pair[0])) return pair[1];
        if (std.mem.eql(u8, name, pair[1])) return pair[0];
    }
    return null;
}

pub fn loadManifest(allocator: std.mem.Allocator, manifest_path: []const u8, source: Source, detail_dir: []const u8) ![]Masque {
    const file = std.fs.cwd().openFile(manifest_path, .{}) catch {
        return error.ManifestNotFound;
    };
    defer file.close();

    const file_content = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(file_content);

    var yaml: Yaml = .{ .source = file_content };
    defer yaml.deinit(allocator);

    yaml.load(allocator) catch |err| switch (err) {
        error.ParseFailure => return error.ManifestParseError,
        else => return error.ManifestParseError,
    };

    if (yaml.docs.items.len == 0) return error.ManifestEmpty;

    const doc = yaml.docs.items[0];
    const map = switch (doc) {
        .map => |m| m,
        else => return error.ManifestInvalidFormat,
    };

    const masques_val = map.get("masques") orelse return error.ManifestNoMasques;
    const masques_list = switch (masques_val) {
        .list => |l| l,
        else => return error.ManifestInvalidFormat,
    };

    var result = try allocator.alloc(Masque, masques_list.len);
    for (masques_list, 0..) |item, i| {
        const m = switch (item) {
            .map => |m2| m2,
            else => continue,
        };

        const name = if (m.get("name")) |v| (if (v == .scalar) v.scalar else "?") else "?";
        const version = if (m.get("version")) |v| (if (v == .scalar) v.scalar else "0.0.0") else "0.0.0";
        const domain = if (m.get("domain")) |v| (if (v == .scalar) v.scalar else "") else "";
        const tagline = if (m.get("tagline")) |v| (if (v == .scalar) v.scalar else "") else "";

        result[i] = .{
            .name = try allocator.dupe(u8, name),
            .version = try allocator.dupe(u8, version),
            .domain = try allocator.dupe(u8, domain),
            .tagline = try allocator.dupe(u8, tagline),
            .style = "",
            .philosophy = "",
            .complement = try allocator.dupe(u8, findComplement(name) orelse ""),
            .shadow = "",
            .lens_summary = "",
            .lens = "",
            .context = "",
            .category = categorize(domain),
            .abbrev = abbreviate(name),
            .detail_loaded = false,
            .source = source,
            .detail_dir = try allocator.dupe(u8, detail_dir),
        };
    }

    return result;
}

/// Line-based parser for masque YAML files. The zig-yaml library doesn't
/// support YAML block scalars (| and >), which masque files use extensively
/// for lens and context fields. This parser handles the subset of YAML
/// that masque files actually use.
pub fn loadDetail(allocator: std.mem.Allocator, masque: *Masque) !void {
    if (masque.detail_loaded) return;

    var name_lower_buf: [256]u8 = undefined;
    const name_len = @min(masque.name.len, 256);
    for (masque.name[0..name_len], 0..) |c, i| {
        name_lower_buf[i] = std.ascii.toLower(c);
    }
    const name_lower = name_lower_buf[0..name_len];

    const path = try std.fmt.allocPrint(allocator, "{s}/{s}.masque.yaml", .{ masque.detail_dir, name_lower });
    defer allocator.free(path);

    const file = std.fs.cwd().openFile(path, .{}) catch return;
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    // Extract block scalar regions and attribute values by scanning the source.
    // We find the byte ranges for lens, context, and attribute values by looking
    // for their YAML keys and then collecting the indented block that follows.
    const lens_block = extractBlockScalar(source, "lens:");
    const context_block = extractBlockScalar(source, "context:");
    var style_val: ?[]const u8 = null;
    var philosophy_val: ?[]const u8 = null;

    // Parse attributes section for simple key-value pairs
    if (std.mem.indexOf(u8, source, "\nattributes:")) |attr_start| {
        var pos = attr_start + "\nattributes:".len;
        // Skip to next line
        if (std.mem.indexOfScalarPos(u8, source, pos, '\n')) |nl| {
            pos = nl + 1;
        }
        // Read indented lines
        while (pos < source.len) {
            const line_end = std.mem.indexOfScalarPos(u8, source, pos, '\n') orelse source.len;
            const line = source[pos..line_end];
            const trimmed = std.mem.trimLeft(u8, line, " ");

            // End of attributes block: non-empty, non-comment line with no indent
            if (trimmed.len > 0 and trimmed[0] != '#' and countIndent(line) < 2) break;

            if (countIndent(line) >= 2 and trimmed.len > 0 and trimmed[0] != '#') {
                if (parseSimpleKV(trimmed)) |kv| {
                    if (std.mem.eql(u8, kv.key, "style")) {
                        style_val = kv.value;
                    } else if (std.mem.eql(u8, kv.key, "philosophy")) {
                        philosophy_val = kv.value;
                    }
                }
            }
            pos = line_end + 1;
        }
    }

    // Store lens
    if (lens_block) |block| {
        const full = std.mem.trim(u8, block, " \n\t\r");
        if (full.len > 0) {
            masque.lens = try allocator.dupe(u8, full);
            // Extract summary: first sentence or first 200 chars
            var end: usize = @min(full.len, 200);
            if (std.mem.indexOfScalar(u8, full[0..end], '.')) |dot| {
                end = dot + 1;
            } else if (std.mem.indexOf(u8, full[0..end], "\n\n")) |nl| {
                end = nl;
            }
            const summary = std.mem.trim(u8, full[0..end], " \n\t\r");
            if (summary.len > 0) {
                masque.lens_summary = try allocator.dupe(u8, summary);
            }
        }
    }

    // Store context and extract shadow/complement from it
    if (context_block) |block| {
        const ctx = std.mem.trim(u8, block, " \n\t\r");
        if (ctx.len > 0) {
            masque.context = try allocator.dupe(u8, ctx);

            if (std.mem.indexOf(u8, ctx, "Your shadow:")) |idx| {
                const shadow_start = idx + "Your shadow:".len;
                const shadow_end = if (std.mem.indexOf(u8, ctx[shadow_start..], "\n\n")) |e|
                    shadow_start + e
                else
                    ctx.len;
                const raw = std.mem.trim(u8, ctx[shadow_start..shadow_end], " \n\t");
                if (raw.len > 0) {
                    masque.shadow = try allocator.dupe(u8, raw);
                }
            }

            if (std.mem.indexOf(u8, ctx, "Your complement is")) |idx| {
                const after = ctx[idx + "Your complement is ".len ..];
                if (std.mem.indexOfScalar(u8, after, '.')) |dot| {
                    const comp_name = std.mem.trim(u8, after[0..dot], " ");
                    if (comp_name.len > 0 and comp_name.len < 30) {
                        masque.complement = try allocator.dupe(u8, comp_name);
                    }
                }
            }
        }
    }

    if (style_val) |v| {
        const s = unquote(v);
        if (s.len > 0) masque.style = try allocator.dupe(u8, s);
    }
    if (philosophy_val) |v| {
        const s = unquote(v);
        if (s.len > 0) masque.philosophy = try allocator.dupe(u8, s);
    }

    masque.detail_loaded = true;
}

fn countIndent(line: []const u8) usize {
    var n: usize = 0;
    for (line) |c| {
        if (c == ' ') {
            n += 1;
        } else break;
    }
    return n;
}

const KV = struct { key: []const u8, value: []const u8 };

fn parseSimpleKV(line: []const u8) ?KV {
    const colon_pos = std.mem.indexOf(u8, line, ": ") orelse return null;
    const key = line[0..colon_pos];
    const value = std.mem.trimLeft(u8, line[colon_pos + 2 ..], " ");
    return .{ .key = key, .value = value };
}

fn unquote(s: []const u8) []const u8 {
    if (s.len >= 2) {
        if ((s[0] == '"' and s[s.len - 1] == '"') or
            (s[0] == '\'' and s[s.len - 1] == '\''))
        {
            return s[1 .. s.len - 1];
        }
    }
    return s;
}

/// Find a YAML block scalar in source. Looks for "\nkey: |" (or ">") at column 0,
/// then returns the full indented block that follows as a single slice.
fn extractBlockScalar(source: []const u8, key: []const u8) ?[]const u8 {
    // Search for "\nkey" at column 0
    const needle = key;
    var search_pos: usize = 0;
    while (search_pos < source.len) {
        const found = std.mem.indexOfPos(u8, source, search_pos, needle) orelse return null;
        // Must be at start of line (pos 0 or preceded by \n)
        if (found > 0 and source[found - 1] != '\n') {
            search_pos = found + 1;
            continue;
        }
        // Check what follows the key — should be " |", " >", or just whitespace+newline
        var pos = found + needle.len;
        // Skip spaces
        while (pos < source.len and source[pos] == ' ') : (pos += 1) {}
        // Accept |, >, or immediate newline
        if (pos < source.len and (source[pos] == '|' or source[pos] == '>')) {
            pos += 1;
        }
        // Skip to end of line
        while (pos < source.len and source[pos] != '\n') : (pos += 1) {}
        if (pos < source.len) pos += 1; // skip the \n

        // Now collect all indented lines (indent >= 2)
        const block_start = pos;
        var block_end = block_start;
        while (pos < source.len) {
            const line_start = pos;
            const line_end = std.mem.indexOfScalarPos(u8, source, pos, '\n') orelse source.len;
            const line = source[line_start..line_end];
            const trimmed = std.mem.trimLeft(u8, line, " ");

            if (trimmed.len == 0) {
                // Blank line — include it (preserves paragraph breaks)
                block_end = line_end;
                pos = if (line_end < source.len) line_end + 1 else source.len;
                continue;
            }

            // Comment lines within the block
            if (trimmed[0] == '#' and countIndent(line) >= 2) {
                block_end = line_end;
                pos = if (line_end < source.len) line_end + 1 else source.len;
                continue;
            }

            if (countIndent(line) >= 2) {
                block_end = line_end;
                pos = if (line_end < source.len) line_end + 1 else source.len;
            } else {
                break; // Dedented — end of block
            }
        }

        if (block_end > block_start) {
            return source[block_start..block_end];
        }
        return null;
    }
    return null;
}

pub fn deinitMasques(allocator: std.mem.Allocator, masques: []Masque) void {
    for (masques) |m| {
        // Fields always duped in loadManifest
        allocator.free(m.name);
        allocator.free(m.version);
        allocator.free(m.domain);
        allocator.free(m.tagline);
        allocator.free(m.complement);
        allocator.free(m.detail_dir);
        // Fields duped in loadDetail (only if non-empty, otherwise string literals)
        if (m.detail_loaded) {
            if (m.lens_summary.len > 0) allocator.free(m.lens_summary);
            if (m.lens.len > 0) allocator.free(m.lens);
            if (m.context.len > 0) allocator.free(m.context);
            if (m.style.len > 0) allocator.free(m.style);
            if (m.philosophy.len > 0) allocator.free(m.philosophy);
            if (m.shadow.len > 0) allocator.free(m.shadow);
        }
    }
    allocator.free(masques);
}

/// Merge two masque lists. Primary (private) takes precedence on name collision.
/// Frees shadowed entries from the secondary list. Returns a single merged slice.
pub fn mergeMasques(allocator: std.mem.Allocator, primary: []Masque, secondary: []Masque) ![]Masque {
    if (primary.len == 0) return secondary;
    if (secondary.len == 0) return primary;

    // Count how many secondary masques are NOT shadowed by primary
    var kept: usize = 0;
    for (secondary) |s| {
        var shadowed = false;
        for (primary) |p| {
            if (std.mem.eql(u8, p.name, s.name)) {
                shadowed = true;
                break;
            }
        }
        if (!shadowed) kept += 1;
    }

    var result = try allocator.alloc(Masque, primary.len + kept);

    // Copy all primary masques first
    @memcpy(result[0..primary.len], primary);

    // Copy non-shadowed secondary masques
    var ri: usize = primary.len;
    for (secondary) |s| {
        var shadowed = false;
        for (primary) |p| {
            if (std.mem.eql(u8, p.name, s.name)) {
                shadowed = true;
                break;
            }
        }
        if (shadowed) {
            // Free the shadowed entry
            allocator.free(s.name);
            allocator.free(s.version);
            allocator.free(s.domain);
            allocator.free(s.tagline);
            allocator.free(s.complement);
            allocator.free(s.detail_dir);
        } else {
            result[ri] = s;
            ri += 1;
        }
    }

    // Free the original slices (but not the elements — they've been moved)
    allocator.free(primary);
    allocator.free(secondary);

    return result;
}

/// Resolve the private masques directory: $MASQUES_HOME or ~/.masques
pub fn resolvePrivateDir() ?[]const u8 {
    if (std.posix.getenv("MASQUES_HOME")) |home| return home;
    if (std.posix.getenv("HOME")) |home| {
        var buf: [512]u8 = undefined;
        const path = std.fmt.bufPrint(&buf, "{s}/.masques", .{home}) catch return null;
        // Check if directory exists
        std.fs.cwd().access(path, .{}) catch return null;
        // Return the env-based string for later use (caller will need to format it)
        return home;
    }
    return null;
}
