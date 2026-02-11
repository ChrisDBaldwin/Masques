/// Character density gradients and domain-specific glyph sets.
/// Maps float density [0.0..1.0] to characters from sparse to dense.

/// Standard density gradient: space → dense block
pub const density = " .:=+*#@M";

/// Get a character from the density gradient
pub fn densityChar(level: f32) u8 {
    const clamped = if (level < 0.0) @as(f32, 0.0) else if (level > 1.0) @as(f32, 1.0) else level;
    const idx: usize = @intFromFloat(clamped * @as(f32, @floatFromInt(density.len - 1)));
    return density[idx];
}

/// Domain-specific glyph sets add character to the patterns
pub const DomainGlyphs = struct {
    structural: []const u8, // Primary pattern chars
    connectors: []const u8, // Connecting/flow chars
    accents: []const u8, // Decorative accents
};

pub fn domainGlyphs(domain_category: DomainCategory) DomainGlyphs {
    return switch (domain_category) {
        .cybernetic => .{
            .structural = "><=[]{}|",
            .connectors = "~-=",
            .accents = "().",
        },
        .historical => .{
            .structural = "abcdefgh",
            .connectors = "._~",
            .accents = "\"'`",
        },
        .structural => .{
            .structural = "/\\|_+X",
            .connectors = "-=",
            .accents = ".",
        },
        .synthesis => .{
            .structural = "~^v",
            .connectors = "-_/\\",
            .accents = ".",
        },
        .leverage => .{
            .structural = "/\\|_^",
            .connectors = "-=",
            .accents = "oO",
        },
        .forge => .{
            .structural = "*+#",
            .connectors = ".:=",
            .accents = "'^",
        },
        .executive => .{
            .structural = "|#=",
            .connectors = "-_",
            .accents = ".",
        },
        .analytics => .{
            .structural = ".oO*+",
            .connectors = "-|_",
            .accents = "~",
        },
        .meta => .{
            .structural = "|:.",
            .connectors = "-=",
            .accents = "~*",
        },
        .art => .{
            .structural = "~*oO@",
            .connectors = "._-",
            .accents = "'`^",
        },
    };
}

pub const DomainCategory = enum {
    cybernetic,
    historical,
    structural,
    synthesis,
    leverage,
    forge,
    executive,
    analytics,
    meta,
    art,

    pub fn fromDomain(domain: []const u8) DomainCategory {
        const std = @import("std");
        if (std.mem.eql(u8, domain, "cybernetic-systems")) return .cybernetic;
        if (std.mem.eql(u8, domain, "historical-pattern-analysis")) return .historical;
        if (std.mem.eql(u8, domain, "structural-abstraction")) return .structural;
        if (std.mem.eql(u8, domain, "cross-domain-synthesis")) return .synthesis;
        if (std.mem.eql(u8, domain, "leverage-intervention")) return .leverage;
        if (std.mem.eql(u8, domain, "applied-competence")) return .forge;
        if (std.mem.eql(u8, domain, "systems-programming")) return .forge;
        if (std.mem.eql(u8, domain, "database-architecture")) return .forge;
        if (std.mem.eql(u8, domain, "frontend-analytics")) return .analytics;
        if (std.mem.eql(u8, domain, "masque-creation")) return .meta;
        if (std.mem.eql(u8, domain, "masque-evaluation")) return .meta;
        // Art domains
        if (std.mem.eql(u8, domain, "terminal-interfaces")) return .art;
        if (std.mem.eql(u8, domain, "web-frontend")) return .art;
        if (std.mem.eql(u8, domain, "ios-design")) return .art;
        if (std.mem.eql(u8, domain, "android-design")) return .art;
        if (std.mem.eql(u8, domain, "3d-art")) return .art;
        if (std.mem.eql(u8, domain, "high-art")) return .art;
        if (std.mem.eql(u8, domain, "low-art")) return .art;
        if (std.mem.eql(u8, domain, "creative-encouragement")) return .art;
        // Executive domains
        if (std.mem.eql(u8, domain, "corporate-governance")) return .executive;
        if (std.mem.eql(u8, domain, "executive-leadership")) return .executive;
        if (std.mem.eql(u8, domain, "revenue")) return .executive;
        if (std.mem.eql(u8, domain, "finance")) return .executive;
        if (std.mem.eql(u8, domain, "legal-compliance")) return .executive;
        if (std.mem.eql(u8, domain, "engineering-leadership")) return .executive;
        if (std.mem.eql(u8, domain, "marketing-growth")) return .executive;
        if (std.mem.eql(u8, domain, "operations")) return .executive;
        if (std.mem.eql(u8, domain, "people-culture")) return .executive;
        if (std.mem.eql(u8, domain, "product-management")) return .executive;
        if (std.mem.eql(u8, domain, "technology-strategy")) return .executive;
        return .forge; // default fallback
    }
};
