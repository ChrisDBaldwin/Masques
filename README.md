<p align="center">
  <img src="assets/masques-banner.svg" alt="Masques" width="600">
</p>

# Masques

**AssumeRole for Agents.** A masque is a temporary cognitive identity—bundling lens (how to think), context (who you're helping), and attributes (metadata) into a single assumable primitive.

## What Is This?

Agents today get configured through scattered mechanisms: system prompts, MCP servers, environment variables, knowledge bases. These are disconnected. Masques unifies them into a single "become this identity" operation.

When you don a masque, you get cognitive framing, situational context, and performance scoring via OTEL telemetry. The [roadmap](#roadmap) extends this to bundled knowledge, credentials, tools, and author payments.

## Architecture

```
Agent dons masque
  → session created
  → OTEL metrics/logs flow through collector → ClickHouse + JSONL

Agent works with masque
  → api_requests metered, tool usage tracked
  → DuckDB scores session performance locally

Agent doffs masque
  → session closed, performance scored
```

Two databases today, a third planned:

| Engine | Role | Data |
|--------|------|------|
| **ClickHouse** | Analytics | Telemetry, metering, reputation |
| **DuckDB** | Local scoring | Session performance from OTEL JSONL exports |
| **TigerBeetle** | *(Planned)* Ledger of record | Account balances, transfers, two-phase payments |

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
name: string              # Required. Human-readable name
version: "x.y.z"          # Required. Semantic version

attributes:               # Optional. Flexible metadata
  domain: string
  tagline: string
  style: string
  philosophy: string

context: |                # Optional. Situational framing
  Who you're helping, what they value, operational environment.

lens: |                   # Required. Cognitive framing (system prompt fragment)
  How to approach problems. What to prioritize. What to reject.

spinnerVerbs:             # Optional. Custom activity indicators
  mode: replace           # replace | append | prepend
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

Analytics and payment infrastructure schema — identity, metering, reputation, ledger mirrors, and settlements. See [sql/README.md](sql/README.md) for the full schema and migration instructions.

## Roadmap

Masques is the **identity layer** in an agentic ecosystem. Today it provides cognitive framing (lens, context, attributes) and telemetry-based scoring. The vision extends to full ecosystem integration:

| Need | Status | Why | Approach |
|------|--------|-----|----------|
| Telemetry | **Working** | Measure what masques actually do | OTEL → Collector → ClickHouse + DuckDB |
| Knowledge | Planned | Masques should bring their own context | MCP URIs bundled per masque |
| Credentials | Planned | Identity implies access | Vault role + TTL declarations |
| Tools | Planned | Masques should bring their own capabilities | Bundled MCP servers per masque |
| Payments | Planned | Authors should earn income from their work | TigerBeetle ledger, 402-gated access, author settlement |

## Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](docs/getting-started.md) | Create your first masque in 5 minutes |
| [Vision](docs/vision.md) | The theater metaphor and why masques exist |
| [Concepts](docs/concepts.md) | The five components explained |
| [Schema](docs/schema.md) | Full YAML specification |
| [OTEL Setup](docs/otel-setup.md) | Configuring the telemetry pipeline |
| [Evaluation & Reputation](docs/evaluation.md) | DuckDB session scoring and ClickHouse reputation |
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

Claude Code plugin with OTEL telemetry, ClickHouse analytics, and DuckDB performance scoring. Payment infrastructure (TigerBeetle) is designed but not yet integrated.

---

<p align="center">
  <em>Temporary identities. Coherent work. Measured performance.</em>
</p>
