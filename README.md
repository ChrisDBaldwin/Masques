<p align="center">
  <img src="assets/masques-banner.svg" alt="Masques" width="600">
</p>

# Masques

**AssumeRole for Agents.** A masque is a temporary cognitive identity—bundling intent, context, knowledge, access, and lens into a single assumable primitive.

## What Is This?

Agents today get configured through scattered mechanisms: system prompts, MCP servers, environment variables, knowledge bases. These are disconnected. Masques unifies them into a single "become this identity" operation.

When you don a masque, you get everything: goals, context, knowledge pointers, credentials, and cognitive framing. Masques can even bundle MCP servers to provide domain-specific tools.

## Quick Start

```bash
# Install as a Claude Code plugin
claude plugins add github:ChrisDBaldwin/masques
```

### Commands

```bash
/don <masque> [intent]    # Assume a masque identity
/id                       # Show active masque info
/list                     # List available masques
/inspect [masque]         # View full masque details
```

## Schema

A masque bundles five components into a single YAML file:

```yaml
name: string              # Human-readable name
index: integer            # Unique numeric ID
version: "x.y.z"          # Semantic version
ring: player              # Trust level: admin | player | guest | outsider

attributes:               # Flexible metadata
  domain: string
  tagline: string

intent:                   # What this masque can and cannot do
  allowed:
    - "implement *"       # Glob patterns for allowed actions
    - "design *"
  denied:
    - "rush *"            # Hard boundaries

context: |                # Situational framing
  Who you're helping, what they value, operational environment.

knowledge:                # MCP URIs for knowledge lookup
  - mcp://server/resource

access:                   # Credential configuration
  vault_role: role-name
  ttl: session

lens: |                   # Cognitive framing (system prompt fragment)
  How to approach problems. What to prioritize. What to reject.

mcp:                      # Optional: bundled MCP servers
  servers:
    - name: server-name
      type: stdio
      command: npx
      args: ["-y", "@package/name"]
```

See [Schema Reference](docs/schema.md) for the full specification.

## Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](docs/getting-started.md) | Create your first masque in 5 minutes |
| [Vision](docs/vision.md) | The theater metaphor and why masques exist |
| [Concepts](docs/concepts.md) | The five components explained |
| [Schema](docs/schema.md) | Full YAML specification |
| [Evaluations](evals/README.md) | Testing masque behavioral fidelity |

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before starting.

**The process:** Open an issue first, then fork, branch, and submit a PR referencing that issue.

## Support

This is a personal project maintained in spare time. For bugs, please [open an issue](https://github.com/ChrisDBaldwin/masques/issues/new?template=bug_report.md) with:

- What you tried and what happened
- A screenshot or GIF of the experience (really helps!)
- Your environment details

## Status

Claude Code plugin for YAML-based masque definitions with MCP server bundling.

---

<p align="center">
  <em>Temporary identities. Coherent work.</em>
</p>
