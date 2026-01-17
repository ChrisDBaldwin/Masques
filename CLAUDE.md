# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Masque is an agent identity framework — "AssumeRole for Agents." A masque is a temporary cognitive identity an agent can don, bundling five components: intent, context, knowledge, access, and lens. The semantics mirror AWS IAM but extend beyond permissions to include knowledge pointers and cognitive framing.

**Status**: Design documentation complete. Zig implementation in progress.

## Key Concepts

- **Masques**: Temporary identities with five components (intent, context, knowledge, access, lens). Session-scoped; doffed when work completes.
- **Trust Rings**: Continuous qualification system (Admin → Player → Guest → Outsider). Rings evaluate "do you still qualify?" not "do you have permission?"
- **Knowledge as Pointers**: Masques reference MCP servers for knowledge lookups, not embedded content.
- **Versioned Identities**: Masques are pinned to versions; upgrading is deliberate.

## Directory Structure

```
masque/
├── README.md                       # Main design document
├── CLAUDE.md                       # This file
├── docs/
│   ├── schema.md                   # Schema reference guide
│   └── reflection.md               # Reflection model for observability
├── schemas/
│   └── masque.schema.yaml          # Formal JSON Schema for masques
├── personas/                       # Masque definitions
│   └── codesmith.masque.yaml       # Example masque
├── rings/
│   └── README.md                   # Full trust ring model
├── src/                            # Zig implementation
│   ├── main.zig
│   └── root.zig
└── build.zig                       # Zig build system
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
5. Composable — masques can form teams (tank/healer/DPS pattern)
6. Graceful revocation — sessions wind down with dignity

## Implementation Notes

Masques are defined in `.masque.yaml` files — a declarative DSL validated against `schemas/masque.schema.yaml`.

The Zig runtime will provide:
- YAML parsing and schema validation
- Intent pattern matching (glob-style allowed/denied)
- MCP URI resolution for knowledge pointers
- Session management (don/doff lifecycle)
- Reflection queries via DuckDB
