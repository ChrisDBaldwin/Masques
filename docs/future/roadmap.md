# Masques Roadmap — Agent Factory Pivot

**Status:** Draft. Not yet ratified. Refine before committing.
**Last updated:** 2026-05-25

---

## TL;DR

Masques pivots from **in-session identity injection** (an agent dons a masque mid-conversation) to **agent factory** (the MCP server spawns a fresh agent process with the masque baked in as turn-0 system prompt). The surface to any agent ecosystem is an MCP server (`masques-mcp`) exposing `spawn`, `status`, and `terminate`. The Claude Code plugin's `/don` becomes sugar that proxies to the MCP server.

---

## Why we're pivoting

The current model (don/doff a masque inside a live conversation) has four model-behavior problems that won't show up in evals but will erode trust in production:

1. **Doff doesn't actually un-do.** The masque's lens and the work done under it remain in the context window. The "baseline" you return to remembers being the masque. Reputation scoring of subsequent sessions is contaminated.
2. **Mid-stream identity competes with turn-0 instructions.** A system prompt at turn 1 dominates the model. A masque injected at turn 30 is one more message — the model can and does drift back to its original identity under pressure.
3. **The lock is voluntary.** Today's "one masque at a time" is a YAML file the agent is asked to honor. An adversarial or sloppy agent can ignore it. Process boundaries cannot.
4. **Telemetry attribution is ambiguous.** "Was this token emitted as the masque, or during the transition?" — no clean answer when both identities share one context. Reputation scoring depends on clean attribution.

The factory model: each masque session is its own subprocess, started with the masque YAML as its first system prompt. The agent **is** the masque for its lifetime. No drift, no contamination, structural lock, unambiguous telemetry.

---

## Target architecture

Mirrors the whiteboard sketch:

```
   ┌─────────────────┐
   │  Calling agent  │  (Claude Code / Cursor / Cline / SDK / custom)
   │   (any MCP-     │
   │   speaking)     │
   └────────┬────────┘
            │ MCP: spawn(masque, intent)
            ▼
   ┌─────────────────┐         ┌────────────────────┐
   │   masques-mcp   │────────▶│   ClickHouse       │
   │  (agent factory)│  query  │   (reputation)     │
   │                 │         │   masques.ai       │
   │                 │────────▶├────────────────────┤
   │                 │  gate   │   TigerBeetle      │
   │                 │         │   (ledger of $)    │
   └────────┬────────┘         │   masques.ai       │
            │ spawn            └────────────────────┘
            ▼
   ┌─────────────────┐
   │ Masque process  │  (Claude Agent SDK or pluggable backend)
   │  (system prompt │
   │   = masque YAML)│
   └────────┬────────┘
            │ OTEL spans/metrics/logs
            ▼
   ┌─────────────────┐         ┌────────────────────┐
   │  Local OTEL     │────────▶│   DuckDB (local)   │
   │  collector      │         │  - self-knowledge  │
   └─────────────────┘         │  - sampling buffer │
                               └─────────┬──────────┘
                                         │ forward
                                         ▼
                               ┌────────────────────┐
                               │   ClickHouse       │
                               │   (reputation)     │
                               └────────────────────┘
```

**Key shifts from current state:**

- Surface goes from "Claude Code plugin commands" → "MCP server + plugin sugar"
- Identity injection goes from "system prompt mutation at turn N" → "spawn subprocess at turn 0"
- Lock goes from "YAML file the agent reads" → "process boundary"
- Telemetry attribution goes from "best effort" → "tagged at source with `masque.session_id`"
- Payment gate goes from "design doc" → "MCP server enforces before `spawn` returns"

---

## Phased plan

### Phase 0 — Housekeeping
**Size:** ~1 hour
**Deliverables:**
- Fix `bd` database repo-ID mismatch (`bd migrate --update-repo-id`)
- Sync version: `plugin.json` and `marketplace.json` must match
- CHANGELOG entry noting the upcoming pivot so users aren't surprised

### Phase 1 — `masques-mcp` v0: the agent factory
**Size:** ~3-5 days
**Deliverables:**
- MCP server binary exposing three tools:
  - `spawn(masque: string, intent?: string) → { session_id, status }`
  - `status(session_id) → { state, masque, started_at, last_event }`
  - `terminate(session_id) → { final_state, duration_ms }`
- Reads `*.masque.yaml` from `${MASQUES_HOME}` and `${CLAUDE_PLUGIN_ROOT}/personas`
- Spawns Claude Agent SDK subprocess with `lens` + `context` as system prompt
- Session state persisted to `${MASQUES_HOME}/sessions/{uuid}.session.yaml`
- Structured stdout/stderr proxy so the calling agent gets streaming output
- No payment, no reputation gate yet — that's later phases. This is the skeleton.

**Open question:** implementation language (see Open Questions §1).

### Phase 2 — Genericize
**Size:** ~2-3 days
**Deliverables:**
- Update Claude Code plugin: `/don` becomes a thin wrapper that calls `masques-mcp.spawn` and proxies the subprocess; `/doff` calls `terminate`; `/id` and `/list` read MCP session state
- Integration docs for: Cursor, Cline, Claude Agent SDK, custom MCP clients
- `examples/` directory with minimal "hello, Codesmith" snippets for each ecosystem
- README rewrite (audience: agent developers, not Claude Code users specifically)

### Phase 3 — Telemetry pipeline
**Size:** ~3-5 days
**Deliverables:**
- Spawned masque process emits OTEL to local collector, every span tagged with `masque.session_id`, `masque.name`, `masque.version`
- Synthesize span-like records from Claude Code metrics/logs (agents don't natively emit spans — wrap the log stream)
- DuckDB ingests JSONL exports, maintains rolling "self-knowledge" view per masque
- Forward sampled traces to ClickHouse on masques.ai
- Reputation aggregation MV in ClickHouse (build on existing `006_reputation.sql`)

### Phase 4 — Payment rail
**Size:** ~1-2 weeks
**Deliverables:**
- Host TigerBeetle on masques.ai infrastructure (Docker, persistent volume, backup policy)
- Account structure decided (see Open Questions §3): agent prepaid account, author receivable account, escrow account per pending session
- `masques-mcp.spawn`:
  - queries ClickHouse for masque reputation (block if below threshold)
  - queries TigerBeetle for agent balance (block if insufficient)
  - creates pending two-phase transfer (escrow)
  - returns session_id
- `masques-mcp.terminate`:
  - calculates final cost from telemetry (per-token / per-minute / per-tool-call — decision needed)
  - posts the transfer (or partial-post + void remainder)
- Author payout flow: TigerBeetle balance → Solana wallet (devnet first, mainnet behind flag)
- Contact Protocol integration: `spawn` = Tuning + Bond; `terminate` = Settlement; refund/dispute = Disavowal

### Phase 5 — Legibility
**Size:** ~2 days
**Deliverables:**
- README pitched at "any agent developer," not Claude Code users
- `docs/quickstart-adopter.md` — how to integrate masques into your agent stack
- `docs/quickstart-author.md` — how to publish a masque and get paid
- `docs/what-is-masques.md` — cold-reader explainer

### Phase 6 — masques.ai landing page
**Size:** ~half day
**Deliverables:**
- Single static `index.html` (inline CSS, no build step)
- Hero, what-it-is, install/integrate snippet, link to GitHub
- Deploy to Cloudflare Pages / Vercel / Netlify

---

## What gets retired

- **In-session masque switching.** A session has one masque from start to end. Switching means spawning a new session.
- **`.claude/masque.session.yaml` as a lock.** The session file becomes purely advisory (display state for `/id`). The lock is the process boundary.
- **The "agent dons the masque" framing.** Replaced with "the agent commissions a masque-shaped subagent."

## What's preserved

- Masque YAML schema (`lens`, `context`, `attributes`, `spinnerVerbs`) — no changes needed
- All 30+ existing personas — they become spawn targets
- The plugin commands (`/don`, `/doff`, `/id`, `/list`, `/inspect`, `/sync-manifest`, `/audience`, `/performance`) — kept, internally rewired
- TUI for team composition (`tui/masque`) — unchanged
- ClickHouse schema (numbered migrations `001`–`006`) — mostly intact, may need `session_id` column on sessions table
- DuckDB judge service — continues to work on JSONL exports

---

## Open questions for refinement

1. **MCP server language.** Zig (matches TUI + ContactProtocol, single static binary, no runtime) vs Python (Claude Agent SDK is Python-first, faster prototyping). Lean: start in Python for SDK convenience, rewrite hot paths in Zig if profiling demands.
2. **Subprocess I/O proxying.** How does the calling agent receive the spawned masque's output? Options: (a) stream via MCP tool result chunks, (b) the calling agent connects directly to the subprocess via a returned socket/handle, (c) NDJSON over stdout. Each has implications for latency and client complexity.
3. **TigerBeetle account structure.** Prepaid (agent loads balance before `spawn`) vs postpaid (metered, settled later)? Escrow per session vs running balance? See `docs/session-prompts/tigerbeetle-integration.md` for prior thinking.
4. **Pricing model.** Per-session flat? Per-token? Per-minute? Per-tool-call? Determines how much escrow `spawn` needs to lock.
5. **Reputation gate failure mode.** Hard block, soft warning, or dynamic pricing dial? What threshold, who sets it, how appealable.
6. **Solana specifics.** Native SOL or USDC? Mainnet behind a flag, or devnet only until launch? Wallet management for masque authors — managed custody, BYO keys, or both?
7. **Contact Protocol maturity.** Current state at `~/git/ContactProtocol` is "toy minimal implementation in Zig." Co-develop with Phase 4, or wait until CP v1 and ship Phase 4 with a simpler bilateral handshake first?
8. **Backwards compatibility.** How long do we keep the old in-session model working? Options: (a) deprecated-but-functional through v1.x, removed in v2.0; (b) hard cutover at v2.0; (c) feature flag in `plugin.json`.
9. **Multiple concurrent masques per user.** A single user could have several `masques-mcp.spawn` calls in flight (different masques for different parallel tasks). Allowed? Limit? Per-account quota?
10. **The "feeling" loss.** Mid-session don/doff felt like *becoming* the masque. Factory model feels like *commissioning* one. Is there a UX layer that preserves the embodied feel while keeping the process-boundary honesty?

---

## Risk register

- **MCP isn't universal yet.** Cursor and Cline support is recent; older agent frameworks won't have it. Mitigation: keep a fallback CLI binary that wraps the MCP server for shell-out integrations.
- **Spawning subprocesses adds latency.** Cold-start of Claude Agent SDK could be 1-3s. Mitigation: warm pool of pre-spawned blank workers that get the masque applied just-in-time.
- **Payment infra is regulated.** TigerBeetle + Solana = real money. Need to think about KYC, transaction monitoring, refund policies before mainnet. Mitigation: devnet-only through Phase 4, mainnet behind explicit "I understand" gate.
- **The pivot strands existing users.** Anyone who built on the v1.0 in-session model will need to migrate. Mitigation: deprecation period (Open Q §8), migration guide in docs.

---

## Not committing yet

This roadmap is a working draft. Refine the open questions, adjust phasing, then move to beads epics and begin Phase 0.

---

## Update 2026-06-01 — the MCP-server route to this vision

The agent-factory/spawn model above is one way to reach paid masques. A simpler
delivery route emerged: ship Masques as an **MCP server**. The monetization
then gates **MCP tool calls**
rather than spawning processes — cleaner than the escrow-on-don/settle-on-doff
design in `tigerbeetle-integration.md`.

Refined (still deferred) payment vision:
- **Authors are paid per masque use** — the marketplace goal, unchanged.
- Hosted on `masques.ai`, alongside the OpenGander MCP stack (SSE + OAuth2).
- Micropayments via **Solana or TigerBeetle**, with credit-card/wallet ↔
  subscription **budget escrow accounts**: a user funds a budget; dons draw from
  it; authors get paid out. OAuth identity (Phase B) keys both reputation and the
  budget account.
- Phase A (the local, free, stdio MCP server) ships with **none** of this. Payment
  is Phase C, design-only, and stays in `docs/future/`.
