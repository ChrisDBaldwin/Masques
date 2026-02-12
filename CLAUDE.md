# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

Masques applies theater's ancient coordination model to AI agents. Just as actors don costumes, adopt roles, and operate within defined boundaries — then step backstage to become themselves again — agents can temporarily assume identities called masques.

The core problem: today agents get configured through scattered mechanisms (system prompts, MCP servers, credentials, knowledge bases, tool permissions). These are disconnected. A masque unifies cognitive identity into a single "become this" operation — one `don`, one `doff`, session over.

**Masques is "AssumeRole for Agents."** A masque is a temporary cognitive identity bundling lens (how to think), context (situational grounding), and attributes (metadata). Masque authors get paid when their masques are used.

## What Masques Own (and Don't)

Masques own **cognitive identity** — nothing else. Separation of concerns:

| Need | Masques | Who Handles It |
|------|---------|----------------|
| Identity & framing | Lens + context | Masque itself |
| Knowledge lookup | Declares need | MCP servers |
| Credentials | Declares need | Vault/credential managers |
| Tool bundles | Declares capability | Claude Code MCP config |
| Performance tracking | Declares interest | Observability (OTEL) |

## Masque Schema

Every masque is a YAML file with three required fields and three optional fields. The schema is intentionally minimal.

### Required Fields

```yaml
name: string              # Human-readable identifier (minLength: 1)
version: "x.y.z"          # Semantic version (pinned — upgrading is deliberate, not automatic)
lens: |                    # Cognitive framing — the core of the masque
  How to think, how to work, what to refuse.
  This is intent guidance as prose.
```

### Optional Fields

```yaml
attributes:               # Flexible key-value metadata (additionalProperties: true)
  domain: string          # Primary domain (e.g., "systems-programming")
  tagline: string         # One-line promise (e.g., "every line should teach")
  style: string           # Working style description
  philosophy: string      # Core philosophy
  # Any additional keys are allowed

context: |                # Situational grounding
  Who you're helping. What they value.
  What's the operational environment.

spinnerVerbs:             # Custom activity indicators
  mode: replace           # replace | append | prepend
  verbs:                  # min 1 item
    - "Masque:Verbing"    # e.g., "Codesmith:Forging"
```

### What Each Field Means

**Lens** is the identity. It defines *how to think*, not just what to do:
- Core principles and beliefs
- Working style and approach
- Priorities and heuristics
- Boundaries — what to do, what to avoid, what to refuse
- A good lens reads as natural prose and keeps all behavioral guidance in one place

**Context** is the situation. It grounds the identity in a real scenario:
- Who you're helping and what they value
- Constraints of the environment
- What matters right now

**Attributes** are metadata for discovery and display — domain, tagline, style. They describe the masque without affecting behavior directly.

**SpinnerVerbs** give the masque a visual presence during work — custom activity messages.

### What Makes a Good Masque

- **Clear boundaries** — explicit about what to refuse
- **Specific context** — grounded in a real situation with real constraints
- **Coherent lens** — core principles reinforce each other
- **Self-awareness** — knows its occupational hazards (shadow awareness)
- **Actionable guidance** — not just values, but *how to work*
- **Appropriate scope** — focused enough to be coherent, broad enough to be useful

### Session Lifecycle

1. **Don** — agent assumes masque (context + lens injected, spinner verbs applied)
2. **Work** — agent operates with full identity context
3. **Doff** — session ends (state cleared, returns to baseline)

Versions are pinned. If an author updates a masque, you keep using the version you donned until you consciously upgrade. This is opposite to typical prompt evolution (which silently upgrades).

## Two Delivery Surfaces

### 1. Claude Code Plugin

The primary interface. Eight slash commands for identity management:

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

State persists in `.claude/masque.session.yaml`:

```yaml
active:
  name: Codesmith              # null if no masque active
  source: shared               # "private" or "shared"
  donned_at: 2026-01-26T12:00:00Z
previous:
  name: Firekeeper
  source: private
  doffed_at: 2026-01-26T11:00:00Z
```

### 2. TUI — `masque`

A Zig terminal application for visually composing masque teams. Lives in `tui/`.

**Purpose**: Interactive team drafting — browse masques in an animated grid, select members, assign roles, save team compositions.

**Two-screen design**:
- **Lobby** — browse saved teams from `~/.masques/*.team.yaml`, create new ones
- **Draft** — three-panel workspace:
  - *Left*: filterable grid of masque portrait cards (6 tabs: All, Executive, Cognitive, Specialist, Art, Meta)
  - *Right*: detail panel with animated theatrical mask + metadata (name, version, domain, lens excerpt)
  - *Bottom*: team roster with role assignment (Point/Coach) and synergy indicators

**Build and run**:
```bash
cd tui && zig build          # Compile
cd tui && zig build run      # Run immediately
```

Requires Zig 0.15.0+. Dependencies: [libvaxis](https://github.com/rockorager/libvaxis) (TUI framework), [zig-yaml](https://github.com/kubkon/zig-yaml) (YAML parsing).

**Writes to**: `~/.masques/{name}.team.yaml` — team composition files loadable from the lobby.

#### TUI Source Map (`tui/src/`)

| Module | Lines | Purpose |
|--------|-------|---------|
| `main.zig` | ~780 | Event loop, screen routing (lobby/draft), keyboard handling, 30fps animation tick |
| `masque.zig` | ~420 | Masque struct, YAML manifest loading, detail loading, categorization, complement pairs |
| `state.zig` | ~200 | AppState: cursor positions, selections, team members, focus state, screen mode |
| `detail.zig` | ~400 | Detail panel — large theatrical mask + metadata rendering |
| `lobby.zig` | ~340 | Lobby screen — team file discovery, navigation, team creation |
| `grid.zig` | ~250 | Portrait card grid — dynamic columns, cursor/selection state |
| `roster.zig` | ~180 | Team roster — slots, role assignment (Point/Coach), synergy |
| `writer.zig` | ~150 | Serialize team state to `.team.yaml` |
| `portrait.zig` | ~350 | Animated ASCII art per masque with state machine (idle/selecting/selected/deselecting/confirming) |
| `layout.zig` | ~100 | Dynamic panel position/size calculator |
| `color.zig` | ~200 | Domain-to-RGB color mapping (30+ domains, primary/dim/bright) |
| `mask.zig` | ~200 | 5 theatrical mask shapes (classic, sovereign, cerebral, theatrical, geometric) |
| `particle.zig` | ~80 | Fixed-size particle system (64 max) for burst/spark effects |
| `math.zig` | ~100 | Sin/cos LUTs, Xorshift32 PRNG, FNV-1a hash, lerp |
| `gradient.zig` | ~150 | Character density gradients, domain-specific glyph sets |
| `patterns/` | ~800 | 10 domain-specific pattern generators for animated portraits |

**Technical approach**:
- No heap allocations in the hot path — static cell buffers, fixed-size particle arrays
- Lookup tables over runtime math — sin/cos, character density, color mapping all precomputed
- Deterministic randomness — Xorshift32 PRNG seeded per masque name hash
- 30fps animation driven by background thread tick

## Architecture

Three databases, each doing what it's best at:

- **TigerBeetle** — Ledger of record (designed, not yet integrated). Account balances, two-phase transfers (pending on don, posted on doff). Source of truth for all money movement.
- **ClickHouse** — Analytics. Telemetry (OTEL metrics/logs), metering (`api_requests`), reputation scoring, balance snapshots synced from TigerBeetle. Remote, columnar, cost-efficient at scale.
- **DuckDB** — Local performance scoring. Reads OTEL JSONL exports from the collector, scores masque sessions across 5 dimensions. Zero-infrastructure, ephemeral.

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
├── *.masque.yaml                # Private masque definitions
└── *.team.yaml                  # Saved team compositions (from masque TUI)

masques/                         # Plugin repo root
├── CLAUDE.md                    # This file
├── AGENTS.md                    # Agent session workflow (landing the plane)
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest (name, version, description)
├── commands/                    # Plugin slash commands (Markdown specs)
│   ├── don.md                   # /don <masque> - adopt identity
│   ├── doff.md                  # /doff - return to baseline
│   ├── id.md                    # /id - show current identity
│   ├── list.md                  # /list - list masques
│   ├── inspect.md               # /inspect - detailed view
│   ├── sync-manifest.md         # /sync-manifest - regenerate manifests
│   ├── audience.md              # /audience - manage telemetry observers
│   └── performance.md           # /performance - telemetry performance scoring
├── personas/                    # Shared masque definitions (30+ YAML files)
│   ├── manifest.yaml            # Auto-generated listing cache
│   ├── codesmith.masque.yaml
│   ├── firekeeper.masque.yaml
│   ├── mirror.masque.yaml
│   ├── witness.masque.yaml
│   └── ...                      # 25+ more across domains
├── schemas/
│   └── masque.schema.yaml       # JSON Schema for masque validation
├── sql/                         # ClickHouse schema (numbered migrations)
│   ├── README.md                # Schema docs + architecture diagram
│   ├── 001_create_database.sql
│   ├── 002_identities.sql       # Identities + masque sessions
│   ├── 003_ledger.sql           # TigerBeetle account/transaction mirrors
│   ├── 004_settlements.sql      # On-chain/Lightning settlement records
│   ├── 005_metering.sql         # 402-gated API request metering
│   └── 006_reputation.sql       # Reputation events, scores, + MV
├── services/
│   ├── collector/               # OTEL collector (Docker)
│   │   ├── config.yaml          # Dual export: ClickHouse + JSONL
│   │   └── docker-compose.yml
│   └── judge/                   # DuckDB performance scoring
│       ├── judge.sh             # Entry point — runs DuckDB, outputs YAML
│       ├── sessions.sql         # Extract session boundaries from JSONL
│       └── score.sql            # 5-dimension scoring + composite
├── tui/                         # Terminal UI — masque
│   ├── build.zig                # Zig build config (v0.15.0+)
│   ├── build.zig.zon            # Dependency manifest (vaxis, zig-yaml)
│   └── src/                     # Source (see TUI Source Map above)
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
```

## Masque Discovery

Masques are loaded from two locations (private takes precedence):

1. **Private**: `${MASQUES_HOME:-~/.masques}/*.masque.yaml` — personal, not version controlled
2. **Shared**: `${CLAUDE_PLUGIN_ROOT}/personas/*.masque.yaml` — bundled with plugin, version controlled

Manifests (`manifest.yaml` in each location) provide fast listing without scanning every file. Regenerate with `/sync-manifest`.

## Development Workflow

### Issue Tracking — Beads (`bd`)

```bash
bd ready                                    # Find available work (unblocked, unassigned)
bd show <id>                                # View issue details
bd update <id> --status=in_progress         # Claim work
bd close <id>                               # Complete work
bd sync                                     # Sync with git remote
```

### Building

```bash
# TUI
cd tui && zig build          # Compile masque TUI
cd tui && zig build run      # Run the TUI

# Evals
promptfoo eval -c evals/codesmith/promptfooconfig.yaml
promptfoo view               # Interactive results UI

# Services
docker compose -f services/collector/docker-compose.yml up    # OTEL collector
```

### Session Completion

Work is NOT complete until `git push` succeeds. See `AGENTS.md` for the full checklist:

1. File issues for remaining work (`bd create`)
2. Run quality gates if code changed
3. Update issue status (`bd close`)
4. Push to remote: `git pull --rebase && bd sync && git push`
5. Verify with `git status` — must show "up to date with origin"

## Database Conventions

- **TigerBeetle is the ledger of record.** ClickHouse is analytics. Never reverse this.
- **ClickHouse schema lives in `sql/`**, numbered migrations executed in order.
- **DuckDB is ephemeral.** No persistent state. Reads JSONL, scores in-memory, outputs YAML.
- **No hardcoded credentials.** Use `.env` patterns with `.env.example` templates.
- **Writes to files, not databases.** DDL and DML are output for human review, not executed directly.

## Design Principles

1. **Simple** — lens, context, attributes. That's the whole identity.
2. **Session-scoped** — masques are temporary. Don, work, doff.
3. **Versioned** — pin to versions, upgrade deliberately, never silently.
4. **Plugin-first** — YAML source, Claude Code delivery.
5. **Authors get paid** — metered usage, 402-gated, real settlement rails.
6. **Three databases** — TigerBeetle (money), ClickHouse (analytics), DuckDB (local scoring). Each does what it's best at.
7. **Separation of concerns** — masques own identity. MCP owns knowledge. Vaults own credentials. Observability owns metrics.

## Version Management

Plugin version must be updated in **two files** that must stay in sync:

| File | Field | Purpose |
|------|-------|---------|
| `.claude-plugin/plugin.json` | `version` | Plugin manifest (Claude Code reads this) |
| `.claude-plugin/marketplace.json` | `plugins[0].version` | Marketplace listing |

**Bump checklist** (when releasing a new version):
1. Update `plugin.json` version
2. Update `marketplace.json` version (must match)
3. Add CHANGELOG.md entry
4. Commit with message: "Bump to vX.Y.Z"
