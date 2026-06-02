<p align="center">
  <img src="assets/masques-banner.svg" alt="Masques" width="600">
</p>

# Masques

**AssumeRole for Agents.** A masque is a temporary cognitive identity—bundling lens (how to think), context (who you're helping), and attributes (metadata) into a single assumable primitive.

## What Is This?

Agents today get configured through scattered mechanisms: system prompts, MCP servers, environment variables, knowledge bases. These are disconnected. Masques unifies them into a single "become this identity" operation.

It's a representation layer you slap on top of any agent: don a masque to adopt its lens and context, do the work, then doff to step backstage and return to baseline. The core needs **zero infrastructure** — a masque is just YAML, and identity lives in a session file. The [roadmap](#roadmap) sketches where this could grow — bundled knowledge, credentials, and tools.

## Measurable Identity — the differentiated half

A masque without an audience is just a system prompt. The interesting question
isn't that you *wore* a costume — it's whether wearing it made the work **better**.

So the audience is **always seated**: a local, always-on observer captures every
session — masque or baseline — and scores it two ways. From session one you get a
**7-point house reaction** (`perfect · great · good · neutral · bad · awful ·
detracting`) — an honest read of how the session went. As your own baseline corpus
thickens, the audience adds **lift**: how a masque compares to *your* no-masque
baseline on the *same kind of work* — *"Codesmith runs +1.4 on your refactor
work."* A difference, never a vanity number, and it never leaves your machine.

This is the part that makes masques more than prompt presets. See
[`docs/evaluation.md`](docs/evaluation.md) and [`docs/otel-setup.md`](docs/otel-setup.md).

## How It Works

The core loop needs no databases, no services, no credentials — just YAML and a session file:

```
Don   → read masque YAML, inject lens + context, write .claude/masque.session.yaml
Work  → operate with the masque's framing
Doff  → clear the session, return to baseline Claude
```

That don/doff loop needs zero infrastructure. The **audience** that measures it
(above) runs locally and stays on your machine:

| Component | Role | Where |
|-----------|------|-------|
| **OTEL collector** | Always-on capture of every session → local JSONL | Local Docker, seated once (`/audience seat`) |
| **DuckDB judge** | Two-layer scoring (reaction + lift) | Local, ephemeral |
| **ClickHouse** | Remote reputation store *(opt-in, deferred — Tier 3)* | masques.ai, off by default |

The local collector + DuckDB are the measurable-identity layer. Remote forwarding
to masques.ai is strictly opt-in and ships only derived scores — never your
prompts, code, or tool I/O.

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

The always-on audience. Receives metrics and logs from every Claude Code session via OTLP and writes them to local JSONL. **Local-only by default** — nothing leaves the machine. Seated once and left running:

```bash
cd services/collector
docker compose up -d --build   # or: /audience seat — seat the house once
```

### Performance Judge (DuckDB)

Reads the local OTEL exports and emits the **two-layer** score (see [evaluation](docs/evaluation.md)):

- **Layer A — house reaction** (always): a 7-point verdict — `perfect · great · good · neutral · bad · awful · detracting` — from a rubric judge (if the masque carries a `rubric`) or an activity fallback.
- **Layer B — lift** (once earned): the masque's delta vs *your* baseline corpus on the same task-class — never a bare number, never below threshold.

The old activity proxies (tool success, throughput, cost…) are demoted to *supporting signals* — context, not the verdict.

```bash
services/judge/judge.sh   # Outputs the two-layer YAML score to stdout
# or: /performance
```

### ClickHouse (opt-in, deferred)

The remote reputation store (Tier 3, masques.ai). **Off by default** and not wired into the shipping collector — the local audience never depends on it. When enabled it must forward only the derived Tier-2 signal (scores + coarse metadata), never prompts, code, or tool I/O.

## TUI — Masque

Terminal UI for browsing masques and drafting teams. Built with Zig 0.16+ and [libvaxis](https://github.com/rockorager/libvaxis).

```bash
cd tui && zig build run   # build and launch
# or: zig build && ./zig-out/bin/masques
```

- Animated portraits with domain-specific patterns (forge, cybernetic, art, etc.)
- Theatrical mask silhouettes per category — sovereign (executive), cerebral (cognitive), classic (specialist), theatrical (art), geometric (meta)
- Full lens text, attributes, and metadata in the detail panel
- Team drafting with role assignment and YAML export

Navigate with arrow keys, `Enter` to add to team, `Tab` to switch focus, `1`–`6` for category tabs, `q` to quit.

## Roadmap

Masques is the **identity layer** for any agent. Today it provides cognitive framing (lens, context, attributes) and telemetry-based scoring. The minimal product stops there. Possible future integration:

| Need | Status | Why | Approach |
|------|--------|-----|----------|
| Telemetry | **Working** | Measure what masques actually do | OTEL → Collector → ClickHouse + DuckDB |
| Knowledge | Planned | Masques should bring their own context | MCP URIs bundled per masque |
| Credentials | Planned | Identity implies access | Vault role + TTL declarations |
| Tools | Planned | Masques should bring their own capabilities | Bundled MCP servers per masque |

The larger "agent marketplace" direction — spawning masques as paid workers with a reputation + payment gate — is deferred. See [`docs/future/`](docs/future/) for that vision.

## Documentation

| Guide | Description |
|-------|-------------|
| [Getting Started](docs/getting-started.md) | Create your first masque in 5 minutes |
| [Vision](docs/vision.md) | The theater metaphor and why masques exist |
| [Concepts](docs/concepts.md) | The five components explained |
| [Schema](docs/schema.md) | Full YAML specification |
| [OTEL Setup](docs/otel-setup.md) | Configuring the telemetry pipeline |
| [Evaluation](docs/evaluation.md) | DuckDB session scoring |
| [Evaluations](evals/README.md) | Testing masque behavioral fidelity |
| [Future](docs/future/) | Deferred vision — agent marketplace, payments |
| [TUI](tui/) | Masque — terminal UI for browsing and team drafting |

## Contributing

Contributions welcome! Please read [CONTRIBUTING.md](CONTRIBUTING.md) before starting.

**The process:** Open an issue first, then fork, branch, and submit a PR referencing that issue.

## Support

This is a personal project maintained in spare time. For bugs, please [open an issue](https://github.com/ChrisDBaldwin/masques/issues/new?template=bug_report.md) with:

- What you tried and what happened
- A screenshot or GIF of the experience (really helps!)
- Your environment details

## Status

A Claude Code plugin for donning cognitive identities, a library of 35 masques, and a Zig TUI for team drafting. The core is infrastructure-free; telemetry (OTEL → optional ClickHouse + DuckDB scoring) is opt-in. Payment/marketplace infrastructure is deferred (see [`docs/future/`](docs/future/)).

---

<p align="center">
  <em>Temporary identities. Coherent work. Measured performance.</em>
</p>
