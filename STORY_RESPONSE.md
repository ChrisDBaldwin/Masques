# Masques Compiler Implementation Summary

This document summarizes the implementation of `masques compile` and `masques emit` commands based on the vision in STORY.md.

## What Was Built

The identity compiler now supports two new commands:

```
.masque.yaml (source)
       │
       ├──► masques compile ──► standalone binary (with embedded YAML)
       │                              └─► ./codesmith --source (dumps original YAML)
       │
       └──► masques emit --format=claude ──► system prompt to stdout
```

## Key Design Decision: Embedded Source

Compiled binaries embed the original YAML source. This enables:
- **Self-documentation**: `./codesmith --source` dumps the YAML that built it
- **Introspection**: Debug/audit the exact definition that was compiled
- **Re-emission potential**: Binary could emit itself to formats without needing source file

## Files Changed

### 1. `tools/yaml2zig.zig`
Added source embedding to generated Zig code:
```zig
// Original YAML source embedded for --source command
pub const source_yaml = @embedFile("../personas/{name}.masque.yaml");
```

### 2. `src/masque_main.zig`
Added `source`/`--source` command to masque binaries:
```zig
} else if (std.mem.eql(u8, command, "source") or std.mem.eql(u8, command, "--source")) {
    try cmdSource(allocator, &buf);
```

Updated usage to include:
```
  source            Print original YAML definition (--source)
```

### 3. `src/emit.zig` (NEW FILE)
Complete YAML parser and three emit formats:

**Formats:**
- `claude` - System prompt with identity/context/lens/intent/skills/knowledge
- `json` - Structured JSON representation
- `markdown` - Documentation-style markdown

**Claude format output structure:**
```
# Identity
You are {name}, {tagline}.

# Context
{context}

# Cognitive Lens
{lens}

# Intent Boundaries
You are authorized to:
- {allowed patterns}

You must refuse to:
- {denied patterns}

# Skills
- {skill name} ({proficiency level})

# Knowledge Sources
The following MCP servers are available for knowledge lookup:
- {mcp:// URIs}
```

### 4. `src/main.zig`
Added two new commands:

**emit command:**
```zig
} else if (std.mem.eql(u8, command, "emit")) {
    // Parse YAML, emit to requested format
    try cmdEmit(allocator, input_file, format);
```

**compile command:**
```zig
} else if (std.mem.eql(u8, command, "compile")) {
    // Run yaml2zig, then zig build masque
    try cmdCompile(allocator, input_file, output_path);
```

Updated usage:
```
masques - agent identity compiler

Usage: masques <command> [args]

Commands:
  list                           List all masques
  show <name>                    Show details for a masque
  emit <file> [--format=target]  Emit masque to format (claude, json, markdown)
  compile <file> [-o output]     Compile masque to standalone binary
  validate [file]                Validate masque file(s)
  help                           Show this help

Examples:
  masques emit personas/codesmith.masque.yaml --format=claude
  masques compile personas/codesmith.masque.yaml -o ./codesmith
```

### 5. `build.zig`
Added emit module to CLI imports:
```zig
.{ .name = "emit", .module = b.createModule(.{
    .root_source_file = b.path("src/emit.zig"),
    .target = target,
}) },
```

## Testing Instructions

Once on a machine with Zig:

```bash
# 1. Regenerate Zig files with source embedding
zig build generate

# 2. Build a masque binary
zig build masque -Dname=codesmith

# 3. Test source embedding
./zig-out/bin/codesmith --source
# Should output the original codesmith.masque.yaml

# 4. Test emit command
zig build run -- emit personas/codesmith.masque.yaml --format=claude
zig build run -- emit personas/codesmith.masque.yaml --format=json
zig build run -- emit personas/codesmith.masque.yaml --format=markdown

# 5. Test compile command
zig build run -- compile personas/codesmith.masque.yaml -o ./codesmith
./codesmith info
./codesmith --source
```

## Architecture Notes

### Emit vs Compile

- **emit**: Parses YAML at runtime, outputs to stdout in requested format. No compilation step. Good for CI/CD pipelines, quick inspection.

- **compile**: Orchestrates yaml2zig + zig build to produce standalone binary. Binary has embedded YAML source and full runtime capabilities (don/doff/qualify/mesh networking).

### Skills Parsing

Skills are parsed by `emit.zig` directly from YAML for the emit command. The compiled binary's `interface.Masque` struct doesn't currently include skills (they're informational, not used for runtime operations like intent qualification).

If skills need to be available in compiled binaries, future work would:
1. Add `skills` field to `interface.Masque`
2. Update `yaml2zig` to generate skills data
3. Add skills display to binary's `info` command

### Compile Orchestration

The compile command shells out to existing build infrastructure:
1. Run `zig build yaml2zig -- single <input> <output>` to generate Zig
2. Run `zig build masque -Dname=<name>` to compile binary
3. Copy to output path if `-o` specified

This approach reuses existing tooling rather than reimplementing build logic.

## What STORY.md Envisioned vs What's Implemented

| STORY.md | Implemented |
|----------|-------------|
| `masques compile codesmith.masque.yaml -o codesmith.masque` | ✅ `masques compile <file> [-o output]` |
| `masques emit codesmith.masque.yaml --format=claude` | ✅ `masques emit <file> --format=claude` |
| `masques emit codesmith.masque.yaml --format=ralph` | ⏳ Future (ralph format not yet defined) |
| Feedback loop / reflections | ⏳ Future (out of scope for compiler) |

## Next Steps

1. **Test on machine with Zig** - Verify all changes compile and work correctly
2. **Add more emit formats** - ralph, openai, etc. as orchestration frameworks define their needs
3. **Schema validation** - The `validate` command is still a stub
4. **Skills in binaries** - If needed for runtime operations
