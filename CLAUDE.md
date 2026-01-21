# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Masques is an agent identity framework — "AssumeRole for Agents." A masque is a temporary cognitive identity an agent can don, bundling five components: intent, context, knowledge, access, and lens. The semantics mirror AWS IAM but extend beyond permissions to include knowledge pointers and cognitive framing.

**Status**: Design documentation complete. Zig CLI partially implemented (list/show commands work via DuckDB).

## Key Concepts

- **Masques**: Temporary identities with five components (intent, context, knowledge, access, lens). Session-scoped; doffed when work completes.
- **Trust Rings**: Continuous qualification system (Admin → Player → Guest → Outsider). Rings evaluate "do you still qualify?" not "do you have permission?"
- **Knowledge as Pointers**: Masques reference MCP servers for knowledge lookups, not embedded content.
- **Versioned Identities**: Masques are pinned to versions; upgrading is deliberate.

## Directory Structure

```
masques/
├── README.md                       # Project overview and quick start
├── CLAUDE.md                       # This file
├── AGENTS.md                       # Agent-specific instructions
├── docs/
│   ├── concepts.md                 # The five components explained
│   ├── trust-rings.md              # Continuous qualification model
│   ├── teams.md                    # Multi-agent patterns
│   ├── implementation.md           # Masques as programs
│   ├── schema.md                   # Schema reference guide
│   └── reflection.md               # Reflection model for observability
├── schemas/
│   └── masque.schema.yaml          # Formal JSON Schema for masques
├── personas/                       # Masque definitions (YAML source)
│   └── codesmith.masque.yaml       # Example masque
├── entities/
│   └── masques/                    # Runtime masque data (JSON)
│       └── codesmith.masque.json   # JSON version queried by CLI
├── src/                            # Zig implementation
│   ├── main.zig                    # CLI entry point (list, show, validate, help)
│   └── root.zig                    # Library module
├── build.zig                       # Zig build system
└── build.zig.zon                   # Zig package manifest (zuckdb dependency)
```

## Build Commands

```bash
zig build              # Build the project
zig build run          # Build and run
zig build test         # Run tests
```

## Design Principles

1. Intent-driven — every assumption states a goal
2. Session-scoped — masques are temporary
3. Pointer-based — knowledge is looked up, not contained
4. Versioned — pin to versions, upgrade deliberately
5. Composable — masques can form teams
6. Graceful revocation — sessions wind down with dignity

## CLI Commands

```bash
masques list              # List all masques (queries entities/masques/*.json)
masques show <name>       # Show detailed masque information
masques validate          # Validate masque definitions (stub)
masques help              # Show help
```

## Implementation Notes

Masques are defined in `.masque.yaml` files — a declarative DSL validated against `schemas/masque.schema.yaml`. The CLI currently reads JSON from `entities/masques/`.

**Implemented:**
- CLI with list/show commands
- DuckDB integration for JSON queries (via zuckdb)

**Not yet implemented:**
- YAML parsing (CLI reads JSON, not YAML)
- Schema validation
- Intent pattern matching (glob-style allowed/denied)
- MCP URI resolution for knowledge pointers
- Session management (don/doff lifecycle)
- Credential minting
