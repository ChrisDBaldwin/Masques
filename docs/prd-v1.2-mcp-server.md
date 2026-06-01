# PRD: Masques v1.2 — Masques as an MCP Server

**Project:** /Users/chris/git/masques
**Author:** Chris Baldwin + Claude
**Date:** 2026-06-01
**Status:** Draft for review
**Branches off:** `prd-v1.1-persistent-audience` (the `score` tool wraps the v1.1 judge)

---

## Problem Statement

Masques is locked to one delivery surface: the Claude Code plugin. The identity
itself is tool-agnostic YAML, but the operation that *uses* it — compose a masque
into a system-prompt fragment — lives as **prose instructions inside
`commands/don.md`**, interpretable only by Claude Code. So "slaps on top of any
agent" is aspiration, not fact.

The closest thing to a universal plugin bus in the agent ecosystem is **MCP**
(Model Context Protocol) — broadly cross-vendor, consumable by any MCP client.
Exposing Masques as an MCP server makes the costume portable to any tool that
speaks MCP, and — later — gives `masques.ai` a hosted Tier-3 node and a clean
monetization surface (gated MCP tool calls).

**Success looks like:** any MCP client can `list`, `inspect`, and `don` a masque,
and `score` a session, by pointing at a local Masques MCP server — with the exact
same masque content and scoring the plugin uses, from one shared core.

## Key Decisions (resolved 2026-06-01)

- **D1 — One core, many adapters.** Extract a tool-agnostic **core**
  (resolve · compose · list · inspect · score). The Claude Code plugin, the local
  MCP server, and any future hosted server are thin adapters over it. The plugin
  stays; it stops being the only way in.
- **D2 — Phase A is a free, local, stdio MCP server.** No auth, no billing.
  Ships portability immediately and de-risks everything downstream.
- **D3 — Scoring stays LOCAL; the privacy spine is preserved.** The `score` tool
  runs the local DuckDB judge on-device. A future hosted server never sees raw
  sessions — only the derived Tier-2 signal, opt-in (PRD v1.1 D3). The hosted
  server **is** the Tier-3 `masques.ai` node v1.1 already designed. "The server
  never sees your prompts or code" becomes a trust feature.
- **D4 — What's delivered is content + scoring, not persistence.** MCP is
  request/response; it cannot guarantee a persistent system prompt. `don` returns
  the composed identity and the *host* keeps it in context. We sell/serve the
  masque (lens+context+rubric) and the measurable-identity scoring — never a
  "guaranteed persistent identity," because MCP can't promise it. Masques are also
  exposed as MCP **prompts** (the closest native "select an identity" surface)
  where clients support them.
- **D5 — Monetization is deferred (Phase C, design-only), and ladders.**
  - **Start (C1): subscription via OAuth + Stripe.** Proven, low-friction, and it
    **reuses the OpenGander stack** (same OAuth + Stripe), so the hosted phase is
    mostly config + entitlements rather than net-new infra. OAuth identity does
    double duty: paywall *and* the per-user reputation namespace (v1.1 D6).
  - **Evolution (C2): author-payout marketplace.** The strong-feeling end goal —
    **masque authors paid per use**. Micropayments via Solana or TigerBeetle on
    `masques.ai`, with credit-card/wallet ↔ subscription **budget escrow accounts**,
    gating hosted MCP tool calls. Refines (not replaces)
    `docs/future/tigerbeetle-integration.md`: gate *MCP calls*, not
    escrow-on-don/settle-on-doff. Stays in `docs/future/`.
  - Phase A ships with **no payment code**.

## Architecture

```
              ┌──────── core (tool-agnostic) ────────┐
              │  schema · resolve · compose · judge   │
              └──────────────┬───────────────────────┘
            ┌────────────────┼───────────────┬─────────────────┐
            ▼                ▼               ▼                 ▼
     Claude Code        Local MCP        Hosted MCP        file / stdout
      plugin (keep)     server (A)       masques.ai (B,C)   emitter (later)
                        stdio · free     SSE · OAuth · paid
```

### MCP surface (Phase A — local)

| Primitive | Name | Returns |
|-----------|------|---------|
| Tool | `list_masques` | catalog: name, version, domain, tagline, has_rubric (private + bundled, private precedence) |
| Tool | `inspect_masque(name)` | full lens, context, attributes, rubric |
| Tool | `don(name, intent?)` | composed identity block (lens + context + intent framing) — the same content `/don` injects |
| Tool | `doff()` | clears local session state, returns to baseline |
| Tool | `score(session?)` | runs the local judge → the two-layer reaction (Layer A always, Layer B when earned) |
| Prompt | `don-<name>` (one per masque) | the composed identity, as an MCP prompt |
| Resource | `masque://catalog`, `masque://{name}` | read-only discovery |

**Stack:** TypeScript + `@modelcontextprotocol/sdk` (most mature MCP SDK). The
core resolves YAML and composes; `score` shells out to the existing
`services/judge/judge.sh`. No reimplementation of the judge.

**Attribution under MCP (open):** the plugin keys attribution on
`CLAUDE_CODE_SESSION_ID`. An MCP server has no equivalent ambient id; `don` will
accept/return a session id the client can thread, or write local session state.
Detailed in OQ1 — Phase A may record a coarse local session and refine later.

## Phase A — Local stdio MCP server (BUILD)

**Deliverables**
- Extract the tool-agnostic **core** (resolve + compose + list + inspect) from the
  prose in `commands/don.md` / `list.md` / `inspect.md` into real code, so the
  plugin and MCP server share one implementation (no drift).
- A stdio MCP server exposing the tools, prompts, and resources above.
- `score` tool wrapping `services/judge/judge.sh`.
- Docs: how to register the local server in any MCP client (config snippet).

## Phase B — Hosted catalog on masques.ai (DESIGN ONLY)

SSE/HTTP transport + OAuth2 (reuse the OpenGander stack). Serves the public
catalog + reputation aggregates; OAuth identity = the per-user reputation
namespace (v1.1 D6). Free tier; no payment. Tier-3 node of the v1.1 architecture.

## Phase C — Monetization (DESIGN ONLY), in two rungs

**C1 — Subscription (OAuth + Stripe).** The starting model. Entitlements gate
hosted premium masques / reputation / analytics behind a Stripe subscription,
keyed on the Phase-B OAuth identity. Reuses the OpenGander Stripe + OAuth stack —
config + entitlements, not net-new payment infra.

**C2 — Author-payout marketplace.** The evolution: masque authors paid per use.
Solana / TigerBeetle on masques.ai; credit-card/wallet ↔ subscription budget
**escrow** accounts; gate MCP tool calls (cleaner than escrow-on-don). Builds on
`docs/future/{roadmap,tigerbeetle-integration}.md`.

## Acceptance Criteria (Phase A)

- [ ] **M1** — A local stdio MCP server starts and a standard MCP client (e.g. MCP
  Inspector) lists its tools.
- [ ] **M2** — `list_masques` returns the full catalog (≥ the 35 bundled), merging
  private `~/.masques` with bundled `personas/`, private taking precedence.
- [ ] **M3** — `inspect_masque("Firekeeper")` returns its lens, context, attributes,
  and rubric.
- [ ] **M4** — `don("Codesmith", intent?)` returns a composed identity block
  containing the masque's lens + context (the same content the plugin injects).
- [ ] **M5** — Each masque is exposed as an MCP prompt; `prompts/get` for one
  returns the composed identity.
- [ ] **M6** — `score` invokes the local judge and returns the two-layer reaction
  for a session.
- [ ] **M7** — Masque resolution + compose is a single shared core; a parity check
  shows the core's compose output matches what the plugin would inject (no drift).
- [ ] **M8** — Docs show registering the local server in an MCP client, verified
  against at least one real client.

## Open Questions

1. **OQ1 — Session/attribution under MCP.** No ambient `CLAUDE_CODE_SESSION_ID`.
   Does `don` mint+return a session id, take one from the client, or write local
   state keyed by start time? Affects how `score` attributes a session.
2. **OQ2 — Persistence UX.** How loudly do we surface that `don` relies on the host
   keeping the identity in context (D4)? Per-client behavior varies.
3. **OQ3 — Core language / packaging.** TS for the server is settled; does the
   *core* live in TS (and the plugin shells out to it), or stay a thin CLI both
   call? Avoid two compose implementations (M7).
4. **OQ4 — Repo layout.** Monorepo package (`mcp/`) here vs a separate package.
   Keep in-repo for Phase A.
5. **OQ5 — Bundled-masque distribution.** How does the local server find
   `personas/` when installed standalone (not as the plugin)? Vendor them or
   resolve via env.

## Scope Boundary — NOT doing in v1.2

- No hosted server, no SSE, no OAuth (Phase B, design-only).
- No payments, no Solana/TigerBeetle, no escrow, no 402/x402 (Phase C, deferred to
  `docs/future/`).
- No change to the masque schema or to existing personas.
- No removal of the Claude Code plugin — it becomes adapter #1.
