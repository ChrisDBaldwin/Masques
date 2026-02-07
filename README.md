<p align="center">
  <img src="assets/masques-banner.svg" alt="Masques" width="600">
</p>

# Masques

**AssumeRole for Agents.** A masque is a temporary cognitive identity—bundling intent, context, knowledge, access, and lens into a single assumable primitive. Authors get paid when their masques are used.

## What Is This?

Agents today get configured through scattered mechanisms: system prompts, MCP servers, environment variables, knowledge bases. These are disconnected. Masques unifies them into a single "become this identity" operation—and builds a payment layer so masque authors earn income from their work.

When you don a masque, you get everything: goals, context, knowledge pointers, credentials, and cognitive framing. The platform meters usage, scores performance, and settles payments to authors.

## Architecture

```
Agent dons masque
  → session created, pending transfer in TigerBeetle
  → OTEL metrics/logs flow through collector → ClickHouse

Agent works with masque
  → api_requests metered, reputation signals collected
  → DuckDB scores session performance locally

Agent doffs masque
  → TigerBeetle finalizes transfer based on usage
  → ClickHouse gets analytical copy
  → Author's balance increases
```

Three databases, each doing what it's best at:

| Engine | Role | Data |
|--------|------|------|
| **TigerBeetle** | Ledger of record | Account balances, transfers, two-phase payments |
| **ClickHouse** | Analytics | Telemetry, metering, reputation, balance snapshots |
| **DuckDB** | Local scoring | Session performance from OTEL JSONL exports |

## Quick Start

```bash
# Install as a Claude Code plugin
claude plugins add github:ChrisDBaldwin/masques
```

### Commands

```bash
/don <masque> [intent]    # Assume a masque identity
/doff                     # Return to baseline Claude
/id                       # Show active masque info
/list                     # List available masques
/inspect [masque]         # View full masque details
/sync-manifest [scope]    # Regenerate manifest files
/audience [action]        # Manage telemetry (start/stop/status/config/logs)
/performance              # Score masque session performance
```

## Schema

A masque bundles cognitive identity into a single YAML file:

```yaml
# === Core Identity ===
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
  denied:
    - "rush *"            # Hard boundaries

context: |                # Situational framing
  Who you're helping, what they value, operational environment.

lens: |                   # Cognitive framing (system prompt fragment)
  How to approach problems. What to prioritize. What to reject.

# === Integration Points ===
knowledge:                # MCP URIs for ecosystem servers
  - mcp://server/resource

access:                   # Credential declarations for vault tools
  vault_role: role-name
  ttl: session

mcp:                      # Bundled MCP servers for Claude Code
  servers:
    - name: server-name
      type: stdio
      command: npx
      args: ["-y", "@package/name"]

spinnerVerbs:             # Custom activity indicators
  mode: replace           # replace | append
  verbs:
    - "Masque:Verbing"
```

See [Schema Reference](docs/schema.md) for the full specification.

## Services

### OTEL Collector

Receives metrics and logs from Claude Code sessions via OTLP, exports to ClickHouse (remote analytics) and local JSONL (DuckDB scoring).

```bash
cd services/collector
docker compose up -d      # Start collector
# Configure via .env — see .env.example
```

### Performance Judge (DuckDB)

Scores masque sessions across 5 dimensions from local OTEL exports:

- **Quality** (30%) — tool success rate
- **Autonomy** (25%) — agent actions per user prompt
- **Productivity** (20%) — tool completions per minute
- **Token Efficiency** (15%) — cache hit ratio
- **Cost Efficiency** (10%) — cost per tool completion

```bash
services/judge/judge.sh   # Outputs YAML score to stdout
```

### ClickHouse Schema

Payment infrastructure tables for identity, ledger analytics, settlements, metering, and reputation. See [sql/README.md](sql/README.md) for the full schema and migration instructions.

## Ecosystem

Masques is the **identity layer** in an agentic ecosystem. It provides cognitive framing (lens, intent, context) while integrating with other tools:

| Need | Masques declares... | Fulfilled by... |
|------|---------------------|-----------------|
| Knowledge | MCP URIs | MCP servers (Context7, etc.) |
| Credentials | Vault role, TTL | Vault, credential managers |
| Tools | Bundled servers | Claude Code MCP config |
| Payments | 402-gated access | TigerBeetle + settlement rails |
| Telemetry | OTEL export | Collector → ClickHouse + DuckDB |

## Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](docs/getting-started.md) | Create your first masque in 5 minutes |
| [Vision](docs/vision.md) | The theater metaphor and why masques exist |
| [Concepts](docs/concepts.md) | The five components explained |
| [Schema](docs/schema.md) | Full YAML specification |
| [OTEL Setup](docs/otel-setup.md) | Configuring the telemetry pipeline |
| [ClickHouse Schema](sql/README.md) | Payment infrastructure tables |
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

Claude Code plugin with OTEL telemetry, ClickHouse analytics, DuckDB performance scoring, and payment infrastructure (TigerBeetle integration in progress).

---

<p align="center">
  <em>Temporary identities. Coherent work. Authors get paid.</em>
</p>
