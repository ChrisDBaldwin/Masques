const std = @import("std");
const zuckdb = @import("zuckdb");
const masque = @import("masque");
const emit_mod = @import("emit");

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
    } else if (std.mem.eql(u8, command, "emit")) {
        if (args.len < 3) {
            std.debug.print("Usage: masques emit <file.masque.yaml> [--format=<target>]\n", .{});
            std.debug.print("Formats: claude (default), json, markdown\n", .{});
            return;
        }
        const input_file = args[2];
        const format = parseFormatArg(args);
        try cmdEmit(allocator, input_file, format);
    } else if (std.mem.eql(u8, command, "compile")) {
        if (args.len < 3) {
            std.debug.print("Usage: masques compile <file.masque.yaml> [-o output]\n", .{});
            return;
        }
        const input_file = args[2];
        const output_path = parseOutputArg(args);
        try cmdCompile(allocator, input_file, output_path);
    } else if (std.mem.eql(u8, command, "help") or std.mem.eql(u8, command, "--help")) {
        printUsage();
    } else {
        std.debug.print("Unknown command: {s}\n\n", .{command});
        printUsage();
    }
}

fn printUsage() void {
    const usage =
        \\masques - agent identity compiler
        \\
        \\Usage: masques <command> [args]
        \\
        \\Commands:
        \\  list                           List all masques
        \\  show <name>                    Show details for a masque
        \\  emit <file> [--format=target]  Emit masque to format (claude, json, markdown)
        \\  compile <file> [-o output]     Compile masque to standalone binary
        \\  validate [file]                Validate masque file(s)
        \\  help                           Show this help
        \\
        \\Examples:
        \\  masques emit personas/codesmith.masque.yaml --format=claude
        \\  masques compile personas/codesmith.masque.yaml -o ./codesmith
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

fn cmdEmit(allocator: std.mem.Allocator, input_file: []const u8, format: emit_mod.Format) !void {
    // Read the YAML file
    const yaml_content = std.fs.cwd().readFileAlloc(allocator, input_file, 1024 * 1024) catch |err| {
        std.debug.print("Failed to read '{s}': {}\n", .{ input_file, err });
        return;
    };
    defer allocator.free(yaml_content);

    // Parse YAML
    var parser = emit_mod.YamlParser.init(allocator, yaml_content);
    defer parser.deinit();

    var masque_def = parser.parseMasque() catch |err| {
        std.debug.print("Failed to parse '{s}': {}\n", .{ input_file, err });
        return;
    };
    defer masque_def.deinit(allocator);

    // Emit to requested format
    emit_mod.emit(allocator, masque_def, format) catch |err| {
        std.debug.print("Failed to emit: {}\n", .{err});
        return;
    };
}

fn cmdCompile(allocator: std.mem.Allocator, input_file: []const u8, output_path: ?[]const u8) !void {
    // Extract masque name from filename
    const basename = std.fs.path.basename(input_file);
    if (!std.mem.endsWith(u8, basename, ".masque.yaml")) {
        std.debug.print("Error: Input must be a .masque.yaml file\n", .{});
        return;
    }
    const name = basename[0 .. basename.len - ".masque.yaml".len];

    std.debug.print("Compiling {s}...\n", .{name});

    // Step 1: Run yaml2zig to generate Zig code
    const gen_output_path = try std.fmt.allocPrint(allocator, "generated/{s}.zig", .{name});
    defer allocator.free(gen_output_path);

    var yaml2zig_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig", "build", "yaml2zig", "--", "single", input_file, gen_output_path },
    }) catch |err| {
        std.debug.print("Failed to run yaml2zig: {}\n", .{err});
        return;
    };
    defer allocator.free(yaml2zig_result.stdout);
    defer allocator.free(yaml2zig_result.stderr);

    if (yaml2zig_result.term.Exited != 0) {
        std.debug.print("yaml2zig failed:\n{s}\n", .{yaml2zig_result.stderr});
        return;
    }

    // Step 2: Run zig build to compile masque binary
    const name_arg = try std.fmt.allocPrint(allocator, "-Dname={s}", .{name});
    defer allocator.free(name_arg);

    var build_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &.{ "zig", "build", "masque", name_arg },
    }) catch |err| {
        std.debug.print("Failed to run zig build: {}\n", .{err});
        return;
    };
    defer allocator.free(build_result.stdout);
    defer allocator.free(build_result.stderr);

    if (build_result.term.Exited != 0) {
        std.debug.print("Build failed:\n{s}\n", .{build_result.stderr});
        return;
    }

    // Step 3: Copy to output path if specified
    const default_output = try std.fmt.allocPrint(allocator, "zig-out/bin/{s}", .{name});
    defer allocator.free(default_output);

    if (output_path) |out| {
        std.fs.cwd().copyFile(default_output, std.fs.cwd(), out, .{}) catch |err| {
            std.debug.print("Failed to copy to {s}: {}\n", .{ out, err });
            return;
        };
        std.debug.print("Compiled: {s}\n", .{out});
    } else {
        std.debug.print("Compiled: {s}\n", .{default_output});
    }
}

fn parseFormatArg(args: [][]const u8) emit_mod.Format {
    for (args) |arg| {
        if (std.mem.startsWith(u8, arg, "--format=")) {
            const format_str = arg["--format=".len..];
            return emit_mod.Format.fromString(format_str) orelse .claude;
        }
    }
    return .claude; // default
}

fn parseOutputArg(args: [][]const u8) ?[]const u8 {
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "-o") and i + 1 < args.len) {
            return args[i + 1];
        }
    }
    return null;
}

test "simple test" {
    const gpa = std.testing.allocator;
    var list: std.ArrayList(i32) = .empty;
    defer list.deinit(gpa);
    try list.append(gpa, 42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
