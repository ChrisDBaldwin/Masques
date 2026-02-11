const std = @import("std");
const Yaml = @import("yaml").Yaml;

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
    category: Category,
    abbrev: [2]u8,
    detail_loaded: bool,
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

/// Known complement pairs
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

pub fn loadManifest(allocator: std.mem.Allocator, manifest_path: []const u8) ![]Masque {
    const file = std.fs.cwd().openFile(manifest_path, .{}) catch {
        return error.ManifestNotFound;
    };
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    var yaml: Yaml = .{ .source = source };
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
            .category = categorize(domain),
            .abbrev = abbreviate(name),
            .detail_loaded = false,
        };
    }

    return result;
}

pub fn loadDetail(allocator: std.mem.Allocator, masque: *Masque, personas_dir: []const u8) !void {
    if (masque.detail_loaded) return;

    var name_lower_buf: [256]u8 = undefined;
    const name_len = @min(masque.name.len, 256);
    for (masque.name[0..name_len], 0..) |c, i| {
        name_lower_buf[i] = std.ascii.toLower(c);
    }
    const name_lower = name_lower_buf[0..name_len];

    const path = try std.fmt.allocPrint(allocator, "{s}/{s}.masque.yaml", .{ personas_dir, name_lower });
    defer allocator.free(path);

    const file = std.fs.cwd().openFile(path, .{}) catch return;
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    var yaml: Yaml = .{ .source = source };
    defer yaml.deinit(allocator);

    yaml.load(allocator) catch return;

    if (yaml.docs.items.len == 0) return;
    const doc = yaml.docs.items[0];
    const map = switch (doc) {
        .map => |m| m,
        else => return,
    };

    // Extract first ~200 chars of lens as summary + full lens text
    if (map.get("lens")) |lens_val| {
        if (lens_val == .scalar) {
            const lens = lens_val.scalar;
            // Find end of first sentence or first 200 chars
            var end: usize = @min(lens.len, 200);
            // Try to break at sentence boundary
            if (std.mem.indexOfScalar(u8, lens[0..end], '.')) |dot| {
                end = dot + 1;
            } else if (std.mem.indexOf(u8, lens[0..end], "\n\n")) |nl| {
                end = nl;
            }
            const summary = std.mem.trim(u8, lens[0..end], " \n\t\r");
            if (summary.len > 0) {
                masque.lens_summary = try allocator.dupe(u8, summary);
            }
            // Full lens text for detail panel
            const full = std.mem.trim(u8, lens, " \n\t\r");
            if (full.len > 0) {
                masque.lens = try allocator.dupe(u8, full);
            }
        }
    }

    if (map.get("attributes")) |attrs_val| {
        const attrs = switch (attrs_val) {
            .map => |m| m,
            else => return,
        };
        if (attrs.get("style")) |v| {
            if (v == .scalar) masque.style = try allocator.dupe(u8, v.scalar);
        }
        if (attrs.get("philosophy")) |v| {
            if (v == .scalar) masque.philosophy = try allocator.dupe(u8, v.scalar);
        }
    }

    if (map.get("context")) |ctx_val| {
        if (ctx_val == .scalar) {
            const ctx = ctx_val.scalar;
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

    masque.detail_loaded = true;
}

pub fn deinitMasques(allocator: std.mem.Allocator, masques: []Masque) void {
    for (masques) |m| {
        // Fields always duped in loadManifest
        allocator.free(m.name);
        allocator.free(m.version);
        allocator.free(m.domain);
        allocator.free(m.tagline);
        allocator.free(m.complement);
        // Fields duped in loadDetail (only if non-empty, otherwise string literals)
        if (m.detail_loaded) {
            if (m.lens_summary.len > 0) allocator.free(m.lens_summary);
            if (m.lens.len > 0) allocator.free(m.lens);
            if (m.style.len > 0) allocator.free(m.style);
            if (m.philosophy.len > 0) allocator.free(m.philosophy);
            if (m.shadow.len > 0) allocator.free(m.shadow);
        }
    }
    allocator.free(masques);
}
