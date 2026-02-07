# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Masques is an agent identity and payment framework — "AssumeRole for Agents." A masque is a temporary cognitive identity an agent can don, bundling lens (cognitive framing), context (situational grounding), and attributes (metadata). Masque authors get paid when their masques are used.

**Delivery**: Claude Code plugin for identity, with a three-database backend for payments, analytics, and performance scoring.

## Key Concepts

- **Masques**: Temporary identities with lens, context, and attributes. Session-scoped.
- **Lens**: Cognitive framing that shapes how the agent thinks and works, including boundaries.
- **Context**: Situational grounding — who you're helping, what they value.
- **Versioned Identities**: Masques are pinned to versions; upgrading is deliberate.
- **Author Payments**: Masque authors earn income when agents use their masques. Metered usage, 402-gated access.

## Architecture

Three databases, each doing what it's best at:

- **TigerBeetle** — Ledger of record (designed, not yet integrated). Account balances, two-phase transfers (pending on don, posted on doff). Source of truth for all money movement.
- **ClickHouse** — Analytics. Telemetry (OTEL metrics/logs), metering (`api_requests`), reputation scoring, balance snapshots synced from TigerBeetle. Remote, columnar, cost-efficient at scale.
- **DuckDB** — Local performance scoring. Reads OTEL JSONL exports from the collector, scores masque sessions across 5 dimensions. Zero-infrastructure, ephemeral. Evolving toward real-session evals.

Data flow:
```
Agent dons masque → session + pending TigerBeetle transfer
  ↓
OTEL metrics/logs → Collector → ClickHouse (remote) + JSONL (local)
  ↓
Agent doffs masque → TigerBeetle posts transfer → ClickHouse gets analytical copy
  ↓
DuckDB reads JSONL → scores session → /performance outputs YAML
```

## Directory Structure

```
~/.masques/                      # Private masques (user's home)
├── manifest.yaml                # Auto-generated listing cache
├── personal.masque.yaml         # Your private masques here
└── ...

masques/                         # Plugin repo
├── README.md                    # Project overview and architecture
├── CLAUDE.md                    # This file
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── commands/                    # Plugin slash commands
│   ├── don.md                   # /don <masque> - adopt identity
│   ├── doff.md                  # /doff - return to baseline
│   ├── id.md                    # /id - show current identity
│   ├── list.md                  # /list - list masques
│   ├── inspect.md               # /inspect - detailed view
│   ├── sync-manifest.md         # /sync-manifest - regenerate manifests
│   ├── audience.md              # /audience - manage telemetry observers
│   └── performance.md           # /performance - telemetry performance scoring
├── personas/                    # Shared masque definitions (YAML source)
│   ├── manifest.yaml            # Auto-generated listing cache
│   ├── codesmith.masque.yaml
│   ├── chartwright.masque.yaml
│   ├── firekeeper.masque.yaml
│   ├── mirror.masque.yaml
│   └── witness.masque.yaml
├── schemas/
│   └── masque.schema.yaml       # JSON Schema for masques
├── sql/                         # ClickHouse payment infrastructure
│   ├── README.md                # Schema docs + architecture diagram
│   ├── 001_create_database.sql  # masques database
│   ├── 002_identities.sql       # Identities + masque sessions
│   ├── 003_ledger.sql           # TigerBeetle account/transaction mirrors
│   ├── 004_settlements.sql      # On-chain/Lightning settlement records
│   ├── 005_metering.sql         # 402-gated API request metering
│   └── 006_reputation.sql       # Reputation events, scores, + MV
├── services/
│   ├── collector/               # OTEL collector (Docker)
│   │   ├── config.yaml          # Dual export: ClickHouse + JSONL
│   │   └── docker-compose.yml   # Container definition
│   └── judge/                   # DuckDB performance scoring
│       ├── judge.sh             # Entry point — runs DuckDB, outputs YAML
│       ├── sessions.sql         # Extract masque session boundaries from JSONL
│       └── score.sql            # 5-dimension scoring + composite
├── evals/                       # Promptfoo behavioral fidelity tests
│   ├── codesmith/
│   ├── chartwright/
│   ├── firekeeper/
│   └── mirror/
└── docs/
    ├── vision.md                # Theater metaphor and philosophy
    ├── concepts.md              # Components explained
    ├── schema.md                # Schema reference guide
    ├── otel-setup.md            # Telemetry pipeline setup
    └── session-prompts/         # Design session context docs
        └── tigerbeetle-integration.md
```

## Plugin Commands

```bash
/don <masque> [intent]    # Adopt a masque identity
/doff                     # Return to baseline Claude
/id                       # Show current identity state
/list                     # List available masques (reads from manifests)
/inspect [masque]         # Detailed masque introspection
/sync-manifest [scope]    # Regenerate manifest files for fast listing
/audience [action]        # Manage telemetry observers (start/stop/status/config/logs)
/performance             # Show masque performance scoring from telemetry data
```

State is persisted in `.claude/masque.session.yaml`.

## Session State

Active masque state is stored in `.claude/masque.session.yaml` (YAML format):

```yaml
# Auto-managed by masques plugin
active:
  name: Codesmith              # null if no masque active
  source: shared               # "private" or "shared"
  donned_at: 2026-01-26T12:00:00Z
previous:
  name: Firekeeper
  source: private
  doffed_at: 2026-01-26T11:00:00Z
```

When doffed, active fields become null and previous fields populate with the doffed masque's info.

**Note:** We store `source` (private/shared) instead of absolute paths to avoid breakage when plugin versions change. The actual path is reconstructed at runtime from name + source.

## Manifests

Masque listings use pre-built manifest files for fast lookups instead of reading every masque file.

**Locations:**
- Private: `~/.masques/manifest.yaml`
- Shared: `personas/manifest.yaml`

**Format:**
```yaml
# Auto-generated by /sync-manifest - do not edit manually
generated_at: 2026-01-26T15:42:00Z
masques:
  - name: Codesmith
    version: "0.1.0"
    domain: systems-programming
    tagline: "every line should teach"
```

**Workflow:**
- Run `/sync-manifest` after adding/modifying masques
- Run `/sync-manifest private` or `/sync-manifest shared` to update only one
- `/list` reads manifests; if missing, prompts to run `/sync-manifest`

## Masque Discovery Paths

Masques are loaded from two locations (in priority order):

1. **Private masques**: `${MASQUES_HOME:-~/.masques}/*.masque.yaml`
   - User's personal masques, stored outside any repo
   - Not version controlled, completely private
   - Configure location with `MASQUES_HOME` env var

2. **Shared masques**: `${CLAUDE_PLUGIN_ROOT}/personas/*.masque.yaml`
   - Bundled with the plugin or shared in projects
   - Version controlled and shareable

If a masque name exists in both locations, the private version takes precedence.

## Creating a New Masque

**For private masques** (personal, not committed):
1. Create `~/.masques/<name>.masque.yaml`
2. Define required fields (see schema below)
3. Test with `/don <name>`

**For shared masques** (project/team):
1. Create `personas/<name>.masque.yaml`
2. Define required fields: `name`, `version`, `lens`
3. Add optional fields: `attributes`, `context`, `spinnerVerbs`
4. Test with `/don <name>`

## Masque Schema (Quick Reference)

```yaml
name: string        # Required. Human-readable name
version: "x.y.z"    # Required. Semantic version

attributes:         # Optional. Flexible metadata
  domain: string
  tagline: string
  style: string
  philosophy: string

context: |          # Optional. Situational framing
  Who you're helping, what they value.

lens: |             # Required. Cognitive framing + intent guidance
  System prompt fragment.
  Include what to do, what to avoid, how to approach work.

spinnerVerbs:       # Optional. Custom activity indicators
  mode: replace     # replace|append|prepend
  verbs:
    - "Masque:Verbing"
```

## Database Conventions

- **TigerBeetle is the ledger of record.** ClickHouse is analytics. Never reverse this.
- **ClickHouse schema lives in `sql/`**, numbered migrations executed in order.
- **DuckDB is ephemeral.** No persistent state. Reads JSONL, scores in-memory, outputs YAML.
- **No hardcoded credentials.** Use `.env` patterns with `.env.example` templates.
- **Writes to files, not databases.** DDL and DML are output for human review, not executed directly.

## Design Principles

1. Simple — lens, context, attributes. That's it.
2. Session-scoped — masques are temporary.
3. Versioned — pin to versions, upgrade deliberately.
4. Plugin-first — YAML source, Claude Code delivery.
5. Authors get paid — metered usage, 402-gated, real settlement rails.
6. Three databases — TigerBeetle (money), ClickHouse (analytics), DuckDB (local scoring). Each does what it's best at.
