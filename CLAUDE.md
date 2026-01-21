# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Masques is an agent identity compiler — "AssumeRole for Agents." A masque is a temporary cognitive identity an agent can don, bundling five components: intent, context, knowledge, access, and lens. The semantics mirror AWS IAM but extend beyond permissions to include knowledge pointers and cognitive framing.

**Status**: Zig CLI functional with list/show/emit/compile commands. Session management, intent qualification, and mesh networking implemented. Claude Code plugin provides /don, /doff, /id, /list, /inspect commands.

## Key Concepts

- **Masques**: Temporary identities with five components (intent, context, knowledge, access, lens). Session-scoped; doffed when work completes.
- **Trust Rings**: Continuous qualification system (Admin → Player → Guest → Outsider). Rings evaluate "do you still qualify?" not "do you have permission?"
- **Knowledge as Pointers**: Masques reference MCP servers for knowledge lookups, not embedded content.
- **Versioned Identities**: Masques are pinned to versions; upgrading is deliberate.
- **Intent Qualification**: Glob-style pattern matching for allowed/denied actions.

## Directory Structure

```
masques/
├── README.md                       # Project overview and quick start
├── CLAUDE.md                       # This file
├── AGENTS.md                       # Agent-specific instructions
├── STORY.md                        # Project narrative and vision
├── plugin.json                     # Claude Code plugin descriptor
├── docs/
│   ├── vision.md                   # Theater metaphor and why masques exist
│   ├── concepts.md                 # The five components explained
│   ├── trust-rings.md              # Continuous qualification model
│   ├── teams.md                    # Multi-agent patterns
│   ├── implementation.md           # Masques as programs
│   ├── schema.md                   # Schema reference guide
│   └── reflection.md               # Reflection model for observability
├── schemas/
│   └── masque.schema.yaml          # Formal JSON Schema for masques
├── personas/                       # Masque definitions (YAML source)
│   ├── codesmith.masque.yaml       # Systems programming masque
│   └── chartwright.masque.yaml     # Data visualization masque
├── generated/                      # Auto-generated Zig from YAML
│   ├── codesmith.zig
│   └── chartwright.zig
├── entities/
│   └── masques/                    # Runtime masque data (JSON)
│       ├── codesmith.masque.json
│       └── chartwright.masque.json
├── src/                            # Zig implementation (~4,300 lines)
│   ├── main.zig                    # CLI entry point
│   ├── masque_main.zig             # Template for compiled masque binaries
│   ├── root.zig                    # Library module
│   ├── intent.zig                  # Glob-style pattern matching
│   ├── session.zig                 # Session management (don/doff)
│   ├── emit.zig                    # YAML parser and multi-format emitter
│   ├── interface.zig               # Masque struct definitions
│   ├── output.zig                  # JSON output writer
│   └── mesh/                       # Peer-to-peer networking
│       ├── mesh.zig                # MeshCoordinator
│       ├── mdns.zig                # mDNS discovery
│       ├── connection.zig          # TCP connections
│       └── protocol.zig            # Wire protocol
├── tools/
│   └── yaml2zig.zig                # YAML-to-Zig compiler
├── claude-plugin/                  # Claude Code plugin
│   ├── .claude-plugin/plugin.json  # Plugin manifest
│   ├── commands/                   # Slash commands
│   │   ├── don.md                  # /don <masque> - adopt identity
│   │   ├── doff.md                 # /doff - release identity
│   │   ├── id.md                   # /id - show current identity
│   │   ├── list.md                 # /list - list masques
│   │   └── inspect.md              # /inspect - detailed view
│   ├── hooks/
│   │   ├── hooks.json              # Hook definitions
│   │   └── session-start.sh        # Re-inject masque on resume
│   └── skills/
│       └── masques/SKILL.md
├── build.zig                       # Zig build system
└── build.zig.zon                   # Zig package manifest (zuckdb dependency)
```

## Build Commands

```bash
zig build                          # Build the CLI
zig build run                      # Build and run
zig build test                     # Run tests
zig build generate                 # Generate Zig from YAML personas
zig build masques                  # Build all masque binaries
zig build -Dname=codesmith masque  # Build single masque binary
```

## CLI Commands

```bash
masques list                       # List all masques (DuckDB query on JSON)
masques show <name>                # Show detailed masque information
masques emit <file> [--format=X]   # Transform YAML to claude/json/markdown
masques compile <file> [-o out]    # Compile YAML to standalone binary
masques validate                   # Validate masque definitions (stub)
masques help                       # Show help
```

## Masque Binary Commands

Compiled masques (`~/.masques/bin/codesmith`) support:

```bash
codesmith info                     # Show masque metadata
codesmith qualify <intent>         # Check if intent is allowed
codesmith don --intent "..."       # Start session, output lens/context
codesmith doff                     # End session
codesmith source                   # Print original YAML definition
codesmith announce                 # Broadcast presence to mesh
codesmith discover                 # List known peers via mDNS
codesmith message <peer> <json>    # Send message to peer
codesmith listen                   # Start message listener
```

## Claude Code Plugin

The plugin enables identity management within Claude Code sessions:

- `/don <masque>` — Adopt a masque identity
- `/doff` — Release the active masque
- `/id` — Show current identity state
- `/list` — List available masques
- `/inspect <masque>` — Detailed masque introspection

State is persisted in `.claude/masques.local.md`.

## Design Principles

1. Intent-driven — every assumption states a goal
2. Session-scoped — masques are temporary
3. Pointer-based — knowledge is looked up, not contained
4. Versioned — pin to versions, upgrade deliberately
5. Composable — masques can form teams
6. Graceful revocation — sessions wind down with dignity

## Data Flow

### Masque Compilation Pipeline
```
personas/*.masque.yaml → yaml2zig → generated/*.zig → zig build → ~/.masques/bin/*
```

### Session Management
```
don --intent "..." → session.zig → ~/.masques/sessions/*.json → doff
```

### Mesh Networking
```
announce → mDNS (_masques._tcp.local:9475) → discover → message/listen
```

## Implementation Status

**Implemented:**
- CLI with list/show/emit/compile commands
- Custom YAML parser (simplified subset)
- DuckDB integration for JSON queries (via zuckdb)
- Intent qualification with glob patterns
- Session management (don/doff lifecycle)
- Masque binary generation (yaml2zig + build system)
- Mesh networking (mDNS discovery, TCP messaging)
- Claude Code plugin with commands and hooks

**Not yet implemented:**
- Full schema validation
- MCP URI resolution for knowledge pointers
- Credential minting for access component
- Reflection/observability metrics
