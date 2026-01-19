const std = @import("std");
const zuckdb = @import("zuckdb");
const masque = @import("masque");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        printUsage();
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "list")) {
        try cmdList(allocator);
    } else if (std.mem.eql(u8, command, "show")) {
        if (args.len < 3) {
            std.debug.print("Usage: masques show <name>\n", .{});
            return;
        }
        try cmdShow(allocator, args[2]);
    } else if (std.mem.eql(u8, command, "validate")) {
        const file = if (args.len >= 3) args[2] else null;
        try cmdValidate(allocator, file);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help")) {
        printUsage();
    } else {
        std.debug.print("Unknown command: {s}\n\n", .{command});
        printUsage();
    }
}

fn printUsage() void {
    const usage =
        \\masques - agent identity framework
        \\
        \\Usage: masques <command> [args]
        \\
        \\Commands:
        \\  list              List all masques
        \\  show <name>       Show details for a masque
        \\  validate [file]   Validate masque file(s)
        \\  help              Show this help
        \\
    ;
    std.debug.print("{s}", .{usage});
}

fn cmdList(allocator: std.mem.Allocator) !void {
    // Initialize in-memory DuckDB
    var db = zuckdb.DB.init(allocator, ":memory:", .{}) catch |err| {
        std.debug.print("Failed to init DuckDB: {}\n", .{err});
        return;
    };
    defer db.deinit();

    var conn = db.conn() catch |err| {
        std.debug.print("Failed to get connection: {}\n", .{err});
        return;
    };
    defer conn.deinit();

    // Query masque JSON files directly
    const query =
        \\SELECT
        \\    name,
        \\    version,
        \\    ring,
        \\    json_extract_string(attributes, '$.tagline') as tagline
        \\FROM read_json_auto('entities/masques/*.masque.json')
        \\ORDER BY name
    ;

    var rows = conn.query(query, .{}) catch |err| {
        std.debug.print("Query failed: {}\n", .{err});
        std.debug.print("(Do masque files exist in entities/masques/?))\n", .{});
        return;
    };
    defer rows.deinit();

    // Print header
    std.debug.print("\n{s:<20} {s:<10} {s:<10} {s}\n", .{ "NAME", "VERSION", "RING", "TAGLINE" });
    std.debug.print("{s}\n", .{"-" ** 70});

    // Print rows
    var count: usize = 0;
    while (try rows.next()) |row| {
        const name = row.get(?[]const u8, 0) orelse "(unnamed)";
        const version = row.get(?[]const u8, 1) orelse "?";
        const ring = row.get(?[]const u8, 2) orelse "?";
        const tagline = row.get(?[]const u8, 3) orelse "";

        std.debug.print("{s:<20} {s:<10} {s:<10} {s}\n", .{ name, version, ring, tagline });
        count += 1;
    }

    std.debug.print("\n{d} masque(s) found\n", .{count});
}

fn cmdShow(allocator: std.mem.Allocator, name: []const u8) !void {
    var db = zuckdb.DB.init(allocator, ":memory:", .{}) catch |err| {
        std.debug.print("Failed to init DuckDB: {}\n", .{err});
        return;
    };
    defer db.deinit();

    var conn = db.conn() catch |err| {
        std.debug.print("Failed to get connection: {}\n", .{err});
        return;
    };
    defer conn.deinit();

    // Query for specific masque - select scalar columns only
    const query =
        \\SELECT
        \\    name,
        \\    version,
        \\    ring,
        \\    "index",
        \\    context,
        \\    lens,
        \\    json_extract_string(attributes, '$.domain') as domain,
        \\    json_extract_string(attributes, '$.language') as language,
        \\    json_extract_string(attributes, '$.tagline') as tagline,
        \\    json_extract_string(access, '$.vault_role') as vault_role
        \\FROM read_json_auto('entities/masques/*.masque.json')
        \\WHERE lower(name) = lower(?)
    ;

    var rows = conn.query(query, .{name}) catch |err| {
        std.debug.print("Query failed: {}\n", .{err});
        return;
    };
    defer rows.deinit();

    if (try rows.next()) |row| {
        const m_name = row.get(?[]const u8, 0) orelse "(unnamed)";
        const version = row.get(?[]const u8, 1) orelse "?";
        const ring = row.get(?[]const u8, 2) orelse "?";
        const index = row.get(?i64, 3);
        const context = row.get(?[]const u8, 4) orelse "";
        const lens = row.get(?[]const u8, 5) orelse "";
        const domain = row.get(?[]const u8, 6) orelse "";
        const language = row.get(?[]const u8, 7) orelse "";
        const tagline = row.get(?[]const u8, 8) orelse "";
        const vault_role = row.get(?[]const u8, 9) orelse "";

        std.debug.print("\n", .{});
        std.debug.print("=== {s} ===\n\n", .{m_name});

        std.debug.print("Version:    {s}\n", .{version});
        std.debug.print("Ring:       {s}\n", .{ring});
        if (index) |idx| {
            std.debug.print("Index:      {d}\n", .{idx});
        }
        if (tagline.len > 0) {
            std.debug.print("Tagline:    \"{s}\"\n", .{tagline});
        }
        std.debug.print("\n", .{});

        if (domain.len > 0 or language.len > 0) {
            std.debug.print("Attributes:\n", .{});
            if (domain.len > 0) std.debug.print("  domain:   {s}\n", .{domain});
            if (language.len > 0) std.debug.print("  language: {s}\n", .{language});
            std.debug.print("\n", .{});
        }

        if (vault_role.len > 0) {
            std.debug.print("Access:\n", .{});
            std.debug.print("  vault_role: {s}\n", .{vault_role});
            std.debug.print("\n", .{});
        }

        if (context.len > 0) {
            std.debug.print("Context:\n", .{});
            // Print first 200 chars
            const ctx_preview = if (context.len > 200) context[0..200] else context;
            std.debug.print("  {s}{s}\n\n", .{ ctx_preview, if (context.len > 200) "..." else "" });
        }

        if (lens.len > 0) {
            std.debug.print("Lens:\n", .{});
            // Print first 300 chars
            const lens_preview = if (lens.len > 300) lens[0..300] else lens;
            std.debug.print("  {s}{s}\n", .{ lens_preview, if (lens.len > 300) "..." else "" });
        }
    } else {
        std.debug.print("Masque '{s}' not found\n", .{name});
    }
}

fn cmdValidate(allocator: std.mem.Allocator, file: ?[]const u8) !void {
    _ = allocator;
    _ = file;
    std.debug.print("validate: not yet implemented\n", .{});
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
