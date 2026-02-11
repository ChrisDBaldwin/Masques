/// Domain color map — primary, dim, and bright variants as RGB triplets.
/// Used by vaxis.Color.rgb for truecolor output.

const std = @import("std");
const vaxis = @import("vaxis");

pub const ColorTriple = struct {
    primary: [3]u8,
    dim: [3]u8,
    bright: [3]u8,
};

pub fn domainColors(domain: []const u8) ColorTriple {
    if (std.mem.eql(u8, domain, "cybernetic-systems")) return .{
        .primary = .{ 0, 206, 209 }, // cyan
        .dim = .{ 0, 103, 105 },
        .bright = .{ 100, 255, 255 },
    };
    if (std.mem.eql(u8, domain, "historical-pattern-analysis")) return .{
        .primary = .{ 218, 165, 32 }, // amber
        .dim = .{ 109, 83, 16 },
        .bright = .{ 255, 215, 100 },
    };
    if (std.mem.eql(u8, domain, "structural-abstraction")) return .{
        .primary = .{ 218, 112, 214 }, // magenta
        .dim = .{ 109, 56, 107 },
        .bright = .{ 255, 170, 255 },
    };
    if (std.mem.eql(u8, domain, "cross-domain-synthesis")) return .{
        .primary = .{ 50, 205, 50 }, // lime
        .dim = .{ 25, 103, 25 },
        .bright = .{ 130, 255, 130 },
    };
    if (std.mem.eql(u8, domain, "leverage-intervention")) return .{
        .primary = .{ 255, 99, 71 }, // tomato
        .dim = .{ 128, 50, 36 },
        .bright = .{ 255, 160, 140 },
    };
    if (std.mem.eql(u8, domain, "applied-competence")) return .{
        .primary = .{ 255, 140, 0 }, // dark orange
        .dim = .{ 128, 70, 0 },
        .bright = .{ 255, 190, 100 },
    };
    if (std.mem.eql(u8, domain, "masque-creation")) return .{
        .primary = .{ 147, 112, 219 }, // medium purple
        .dim = .{ 74, 56, 110 },
        .bright = .{ 200, 170, 255 },
    };
    if (std.mem.eql(u8, domain, "masque-evaluation")) return .{
        .primary = .{ 119, 136, 153 }, // light slate
        .dim = .{ 60, 68, 77 },
        .bright = .{ 180, 200, 220 },
    };
    if (std.mem.eql(u8, domain, "systems-programming")) return .{
        .primary = .{ 65, 105, 225 }, // royal blue
        .dim = .{ 33, 53, 113 },
        .bright = .{ 130, 160, 255 },
    };
    if (std.mem.eql(u8, domain, "frontend-analytics")) return .{
        .primary = .{ 32, 178, 170 }, // light sea green
        .dim = .{ 16, 89, 85 },
        .bright = .{ 100, 230, 220 },
    };
    if (std.mem.eql(u8, domain, "database-architecture")) return .{
        .primary = .{ 205, 133, 63 }, // peru
        .dim = .{ 103, 67, 32 },
        .bright = .{ 240, 190, 130 },
    };
    // Executive domains
    if (std.mem.eql(u8, domain, "corporate-governance")) return .{
        .primary = .{ 184, 134, 11 },
        .dim = .{ 92, 67, 6 },
        .bright = .{ 240, 200, 80 },
    };
    if (std.mem.eql(u8, domain, "executive-leadership")) return .{
        .primary = .{ 220, 20, 60 },
        .dim = .{ 110, 10, 30 },
        .bright = .{ 255, 100, 120 },
    };
    if (std.mem.eql(u8, domain, "revenue")) return .{
        .primary = .{ 34, 139, 34 },
        .dim = .{ 17, 70, 17 },
        .bright = .{ 100, 200, 100 },
    };
    if (std.mem.eql(u8, domain, "finance")) return .{
        .primary = .{ 70, 130, 180 },
        .dim = .{ 35, 65, 90 },
        .bright = .{ 140, 190, 230 },
    };
    if (std.mem.eql(u8, domain, "legal-compliance")) return .{
        .primary = .{ 139, 115, 85 },
        .dim = .{ 70, 58, 43 },
        .bright = .{ 200, 175, 140 },
    };
    if (std.mem.eql(u8, domain, "engineering-leadership")) return .{
        .primary = .{ 255, 69, 0 },
        .dim = .{ 128, 35, 0 },
        .bright = .{ 255, 140, 80 },
    };
    if (std.mem.eql(u8, domain, "marketing-growth")) return .{
        .primary = .{ 255, 105, 180 },
        .dim = .{ 128, 53, 90 },
        .bright = .{ 255, 170, 220 },
    };
    if (std.mem.eql(u8, domain, "operations")) return .{
        .primary = .{ 112, 128, 144 },
        .dim = .{ 56, 64, 72 },
        .bright = .{ 170, 190, 210 },
    };
    if (std.mem.eql(u8, domain, "people-culture")) return .{
        .primary = .{ 222, 184, 135 },
        .dim = .{ 111, 92, 68 },
        .bright = .{ 255, 225, 190 },
    };
    if (std.mem.eql(u8, domain, "product-management")) return .{
        .primary = .{ 106, 90, 205 },
        .dim = .{ 53, 45, 103 },
        .bright = .{ 170, 155, 255 },
    };
    if (std.mem.eql(u8, domain, "technology-strategy")) return .{
        .primary = .{ 46, 139, 87 },
        .dim = .{ 23, 70, 44 },
        .bright = .{ 100, 200, 140 },
    };
    // Art domains
    if (std.mem.eql(u8, domain, "terminal-interfaces")) return .{
        .primary = .{ 0, 255, 136 }, // terminal green
        .dim = .{ 0, 128, 68 },
        .bright = .{ 130, 255, 200 },
    };
    if (std.mem.eql(u8, domain, "web-frontend")) return .{
        .primary = .{ 99, 102, 241 }, // indigo
        .dim = .{ 50, 51, 121 },
        .bright = .{ 165, 180, 252 },
    };
    if (std.mem.eql(u8, domain, "ios-design")) return .{
        .primary = .{ 0, 122, 255 }, // iOS blue
        .dim = .{ 0, 61, 128 },
        .bright = .{ 100, 180, 255 },
    };
    if (std.mem.eql(u8, domain, "android-design")) return .{
        .primary = .{ 164, 198, 57 }, // android green
        .dim = .{ 82, 99, 29 },
        .bright = .{ 210, 240, 130 },
    };
    if (std.mem.eql(u8, domain, "3d-art")) return .{
        .primary = .{ 255, 111, 97 }, // coral
        .dim = .{ 128, 56, 49 },
        .bright = .{ 255, 180, 170 },
    };
    if (std.mem.eql(u8, domain, "high-art")) return .{
        .primary = .{ 212, 175, 55 }, // gold
        .dim = .{ 106, 88, 28 },
        .bright = .{ 255, 223, 120 },
    };
    if (std.mem.eql(u8, domain, "low-art")) return .{
        .primary = .{ 255, 0, 110 }, // hot pink
        .dim = .{ 128, 0, 55 },
        .bright = .{ 255, 110, 180 },
    };
    if (std.mem.eql(u8, domain, "creative-encouragement")) return .{
        .primary = .{ 85, 180, 90 }, // sap green
        .dim = .{ 43, 90, 45 },
        .bright = .{ 150, 230, 155 },
    };
    // Fallback gray
    return .{
        .primary = .{ 170, 170, 170 },
        .dim = .{ 85, 85, 85 },
        .bright = .{ 220, 220, 220 },
    };
}

/// Convert a ColorTriple.primary to a vaxis.Color
pub fn vaxisColor(c: [3]u8) vaxis.Color {
    return .{ .rgb = c };
}

/// Dim a color by mixing with black (factor 0.0 = black, 1.0 = original)
pub fn dimColor(c: [3]u8, factor: f32) [3]u8 {
    return .{
        @intFromFloat(@as(f32, @floatFromInt(c[0])) * factor),
        @intFromFloat(@as(f32, @floatFromInt(c[1])) * factor),
        @intFromFloat(@as(f32, @floatFromInt(c[2])) * factor),
    };
}

/// Brighten a color by mixing with white
pub fn brightenColor(c: [3]u8, factor: f32) [3]u8 {
    const f = std.math.clamp(factor, 0.0, 1.0);
    return .{
        @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(c[0])) + (255.0 - @as(f32, @floatFromInt(c[0]))) * f, 0, 255)),
        @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(c[1])) + (255.0 - @as(f32, @floatFromInt(c[1]))) * f, 0, 255)),
        @intFromFloat(std.math.clamp(@as(f32, @floatFromInt(c[2])) + (255.0 - @as(f32, @floatFromInt(c[2]))) * f, 0, 255)),
    };
}
