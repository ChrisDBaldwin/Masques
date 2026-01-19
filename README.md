# Masque

**AssumeRole for Agents.** A masque is a temporary cognitive identity an agent can don—bundling intent, context, knowledge, access, and lens into a single assumable primitive.

## The Problem

Agents today get configured through scattered mechanisms:
- System prompts (persona)
- MCP servers (capabilities)
- Environment variables (credentials)
- Knowledge bases (context)

These are disconnected. Switching contexts means manually reconfiguring multiple systems. There's no unified "become this identity" operation.

## The Primitive

A masque bundles five components that work as a system:

| Component | Role | Question |
|-----------|------|----------|
| **Intent** | The *why* | What goals does this masque serve? |
| **Context** | The *who* | Who am I helping? What do they value? |
| **Knowledge** | The *what* | Where do I look things up? |
| **Access** | The *how* | What credentials do I need? |
| **Lens** | The *framing* | How should I think about problems? |

**Intent drives everything.** Without stated intent, you're just collecting access. The other four components exist to serve the intent.

**Context grounds it.** Every masque operates in a situation—a domain, a user, a set of values.

**Knowledge enables it.** Masques point to MCP servers for lookups, not embedded blobs. Knowledge stays fresh at the source.

**Access permits it.** Credentials scoped to the task, minted for the session, expired when done.

**Lens shapes approach.** How to think, what to prioritize, what to reject.

When you assume a masque, you get all five. When the session ends, credentials expire—but work product remains.

## What Makes This Different

- **Intent-first** — Every assumption states a goal, not just a role
- **Continuous qualification** — Trust rings ask "do you *still* qualify?" not "do you have permission?"
- **Pointer-based knowledge** — Masques reference MCP servers, not embedded content
- **Versioned identities** — Pin to versions; upgrading is deliberate
- **Composable teams** — Masques form teams with complementary roles
- **Graceful revocation** — Sessions wind down with dignity

## Quick Example

```yaml
name: Codesmith
version: "0.1.0"
ring: player

intent:
  allowed: ["implement *", "design *", "test *", "explain *"]
  denied: ["ship without tests", "rush *", "skip review"]

context: |
  Building the Masque framework in Zig. The human partner is learning
  Zig alongside you. Prioritize clarity over cleverness.

knowledge:
  - mcp://masque/design-docs
  - mcp://zig/stdlib

access:
  vault_role: masque-developer
  ttl: session

lens: |
  You are Codesmith, a methodical builder of foundational systems.
  Write code that teaches. Small commits. Tests as documentation.
  Build incrementally—each piece should work before adding the next.
```

```bash
# Don the masque (Claude Code command)
/don codesmith "implementing YAML parser"

# Work happens with full identity context...

# Doff when done
/doff
```

## Installation

```bash
# As a Claude Code plugin
claude plugins add github:ChrisDBaldwin/Masque

# Or from source
git clone https://github.com/ChrisDBaldwin/Masque.git
cd Masque && zig build
./scripts/postinstall.sh
```

## Commands

| Command | Description |
|---------|-------------|
| `/don <masque> [intent]` | Assume a masque identity |
| `/doff` | Release current masque |
| `/whoami` | Show active masque info |

**Binary commands** (for mesh networking):
```bash
codesmith announce          # Broadcast presence via mDNS
codesmith discover          # Find peers on local network
codesmith message <peer> <json>  # Send message to peer
codesmith listen            # Start message listener
```

## Status

Zig CLI implemented. Claude Code plugin packaged with prebuilt darwin-arm64 binaries.

## Learn More

- [Concepts](docs/concepts.md) — Why these five components, and how they relate
- [Trust Rings](docs/trust-rings.md) — The continuous qualification model
- [Teams](docs/teams.md) — Multi-agent patterns and conflict resolution
- [Implementation](docs/implementation.md) — Masques as programs
- [Schema Reference](docs/schema.md) — Full YAML specification
- [Reflection](docs/reflection.md) — Observability model
