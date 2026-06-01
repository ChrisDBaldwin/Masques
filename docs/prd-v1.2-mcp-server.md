# PRD: Masques v1.2 — Masques as an MCP Server

**Project:** /Users/chris/git/masques
**Author:** Chris Baldwin + Claude
**Date:** 2026-06-01
**Status:** Draft for review
**Branches off:** `prd-v1.1-persistent-audience` (the `score` tool wraps the v1.1 judge)
**Reuse target:** `~/git/opengander` — `services/mcp-server` (FastMCP + JWT/JWKS auth) and the web app's OAuth 2.1 authorization server (`apps/web/src/{app/oauth,lib/oauth,app/api/oauth}`).

---

## Problem Statement

Masques is locked to one delivery surface — the Claude Code plugin — and the one
operation that *uses* a masque (compose its lens+context into a system-prompt
fragment) lives as **prose instructions inside `commands/don.md`**, executable
only by Claude Code. "Slaps on top of any agent" is therefore aspiration.

The universal interop bus in the agent ecosystem is **MCP**. Exposing Masques as
an MCP server makes the costume portable to any MCP client, and — crucially —
**OpenGander already runs this exact pattern in production** at
`mcp.opengander.io`: a Python **FastMCP** server, OAuth 2.1, hosted behind
`masques.ai`-adjacent infra. The OAuth work (the hard part) is done once and can
be reused. v1.2 leans on that instead of reinventing it.

**Success looks like:** any MCP client can `list` / `inspect` / `don` a masque
(and `score` locally) by pointing at a Masques MCP server — same masque content
and scoring the plugin uses — and the hosted path reuses OpenGander's auth stack
so it's config + entitlements, not net-new infrastructure.

## Key Decisions

- **D1 — One core, many adapters.** Extract a tool-agnostic **core**
  (resolve · compose · list · inspect · score). The Claude Code plugin, the local
  MCP server, and the hosted MCP server are thin adapters over it. The plugin
  stays; it stops being the only way in.
- **D2 — Match the OpenGander stack: Python + FastMCP.** *(Supersedes the earlier
  TypeScript sketch.)* Building the server in Python/FastMCP lets Phase B lift
  OpenGander's `services/mcp-server` auth layer (JWT/JWKS, RFC 9728 discovery,
  WWW-Authenticate middleware, scopes, audit) almost verbatim. The judge stays
  shell+SQL; the `score` tool shells out to `services/judge/judge.sh`.
- **D3 — One server, two transports.** The same FastMCP server runs **stdio**
  (Phase A, local, free, no auth) and **Streamable-HTTP + OAuth** (Phase B,
  hosted). OpenGander's `server.py` already exposes `http_app()`; adding a stdio
  entry point is trivial. Local-vs-hosted is a transport + auth config, not a
  rewrite.
- **D4 — Scoring stays LOCAL; the privacy spine holds.** `score` runs the local
  DuckDB judge on-device and is exposed **only by the local server**. The hosted
  server never scores raw sessions — it serves catalog + masque content +
  reputation aggregates, and only the derived Tier-2 signal opt-in forwards
  (v1.1 D3). "The server never sees your prompts or code" is a trust feature.
- **D5 — We deliver content + scoring, not persistence.** MCP is request/response
  and cannot pin a system prompt. `don` returns the composed identity and the
  *host* keeps it in context. Masques are also exposed as MCP **prompts** (the
  native "select an identity" surface) where clients support them. We never
  promise "guaranteed persistent identity," because MCP can't.
- **D6 — Clone OpenGander's OAuth authorization server onto masques.ai (Phase B).**
  *(OQ1 resolved 2026-06-01.)* OAuth 2.1 with Dynamic Client Registration, JWKS,
  and RFC 8414 metadata already exists in OpenGander's `apps/web`. Masques gets its
  **own independent identity** by cloning that pattern onto `app.masques.ai` — not
  sharing `app.opengander.io`. Keeps Masques' account model, branding, and the
  Phase-C budget/escrow accounts decoupled from OpenGander. Phase A needs none of it.
- **D7 — Postgres is the identity/auth store (Phase B), local-dev + prod.** User
  management and auth scopes live in **Postgres** (local Postgres via docker-compose
  for dev/test; prod Postgres in the masques.ai domain). This one store backs the
  authz server (users, OAuth clients, grants, refresh tokens + revocation, scopes/
  entitlements) and naturally also holds the per-user **reputation namespace**
  (v1.1 D6) and Phase-C **subscription/entitlement** state — one database, not
  three. Phase A uses no database.

## Architecture

```
                 ┌──────────── core (Python, tool-agnostic) ────────────┐
                 │  resolve · compose · list · inspect · score(→judge.sh)│
                 │  + thin CLI (`masque ...`) so the plugin shells out   │
                 └───────────────────────┬──────────────────────────────┘
            ┌────────────────────────────┼───────────────────────────────┐
            ▼                            ▼                               ▼
   Claude Code plugin          Local MCP server (A)            Hosted MCP server (B,C)
   (shells out to CLI)         FastMCP · stdio · free          FastMCP · HTTP+OAuth · masques.ai
                               private + bundled masques        public catalog + reputation
                               score = LOCAL                    no raw data; entitlements gate
```

The hosted server **is** the Tier-3 `masques.ai` node v1.1 designed. It sits
beside the OpenGander MCP server, reusing its auth.

## OpenGander reuse map (the point of this PRD)

| OpenGander asset (`~/git/opengander`) | What it does | Masques reuse |
|---|---|---|
| `services/mcp-server/` (FastMCP scaffold) | Python MCP server, pyproject, Dockerfile, tests, promptfoo | **Fork the structure** for `services/mcp/`; keep layout, swap `tools/` + `db.py` |
| `src/opengander_mcp/server.py` | FastMCP app, Starlette wrapper, health, RFC 9728 endpoint, WWW-Authenticate middleware, uvicorn entry | **Copy near-verbatim**; replace ClickHouse lifespan/tools with masque core |
| `jwt_auth.py` · `jwks.py` · `revocation.py` | RS256 OAuth + HS256 session validation, JWKS fetch/cache, revocation | **Lift verbatim** (Phase B); only the issuer/audience config changes |
| `scopes.py` | tool→scope map, `SUPPORTED_SCOPES`, scope checks | **Adapt** to masque scopes (below) |
| `audit.py` · `tenant.py` | audit logging, tenant isolation | **Audit reused**; tenant → per-user namespace (v1.1 D6) |
| `tools/_common.py`, `tools/*.py` | tool impl pattern (typed args, scope-gated, JSON out) | **Pattern reused**; new tools = list/inspect/don/doff/score |
| `apps/web/src/{app/oauth,lib/oauth,app/api/oauth}`, `.well-known/oauth-authorization-server`, `api/.well-known/jwks.json` | the OAuth 2.1 **authorization server** (the hurdle) | **Share or clone** for masques.ai (Phase B / D6) |
| `services/token-service/` | short-lived HS256 OTEL telemetry tokens | Reference only — narrower than the MCP OAuth; not the authz server |
| `Dockerfile`, `infra/`, ALB `/health` pattern, `mcp.opengander.io` | deploy shape | **Mirror** for `mcp.masques.ai` (Phase B) |
| `promptfoo/` (MCP tool evals) | behavioral tests over the live MCP | **Reuse harness** to test masque tools |

## MCP surface

Scopes (mirroring `scopes.py`): `masque:read` (list/inspect/don/doff),
`masque:score` (local only), `reputation:read` (hosted), `health:read`.

| Primitive | Name | Scope | Local (A) | Hosted (B) | Returns |
|-----------|------|-------|:---:|:---:|---------|
| Tool | `list_masques` | `masque:read` | ✓ | ✓ | catalog: name, version, domain, tagline, has_rubric (private over bundled) |
| Tool | `inspect_masque(name)` | `masque:read` | ✓ | ✓ | full lens, context, attributes, rubric |
| Tool | `don(name, intent?)` | `masque:read` | ✓ | ✓ | composed identity block (lens+context+intent) — what `/don` injects |
| Tool | `doff()` | `masque:read` | ✓ | ✓ | clears local session state |
| Tool | `score(session?)` | `masque:score` | ✓ | ✗ | local judge → two-layer reaction (privacy: local only, D4) |
| Tool | `reputation(masque, task_class?)` | `reputation:read` | — | ✓ | per-(masque,task_class) lift + sample count (v1.1 Phase 3) |
| Prompt | `don-<name>` (one per masque) | — | ✓ | ✓ | composed identity, as an MCP prompt |
| Resource | `masque://catalog`, `masque://{name}` | `masque:read` | ✓ | ✓ | read-only discovery |

FastMCP tool shape (mirrors `tools/*.py`):

```python
@mcp.tool()
async def don(ctx: Context, name: str, intent: str | None = None) -> dict[str, Any]:
    """Compose a masque identity for the agent to adopt."""
    masque = core.resolve(name)          # private ~/.masques over bundled personas/
    return core.compose(masque, intent)  # {lens, context, identity_block, version, ...}
```

## Phase A — Local stdio MCP server (BUILD)

Free, local, no auth, no billing. Ships portability immediately.

**Deliverables**
- **Core** (Python package): `resolve(name)` (private `~/.masques` precedence over
  bundled `personas/`), `compose(masque, intent?)` → the identity block the plugin
  injects, `list()`, `inspect(name)`. Lifts the logic out of the prose in
  `commands/don.md` / `list.md` / `inspect.md`.
- **Thin CLI** (`masque compose|list|inspect|score`) over the core, so the Claude
  Code plugin can **shell out to it** — one authoritative implementation, no drift
  (this is how M7 is satisfied: the plugin stops re-deriving compose in prose).
- **FastMCP stdio server** exposing the tools, prompts, and resources above
  (`mcp.run(transport="stdio")`).
- **`score` tool** wrapping `services/judge/judge.sh` (local only).
- **Docs**: register the local server in an MCP client (config snippet).

Repo layout: `services/mcp/` (Python package `masques_mcp/`, mirroring
OpenGander's `services/mcp-server/src/opengander_mcp/`).

## Phase B — Hosted catalog on masques.ai (DESIGN ONLY)

Same FastMCP server, **HTTP transport + OAuth**, reusing OpenGander's auth.

**Design**
- Add `auth=JWTTokenVerifier()`, the RFC 9728 `/.well-known/oauth-protected-resource`
  endpoint, the WWW-Authenticate middleware, and the Starlette wrapper — **copied
  from `server.py`**, retargeted at `mcp.masques.ai` + the masques.ai authz server.
- **OAuth authorization server (decided: clone, D6).** Clone
  `apps/web/src/{app/oauth,lib/oauth,app/api/oauth}` + `.well-known/oauth-authorization-server`
  + `api/.well-known/jwks.json` onto **`app.masques.ai`** — Masques' own IdP, not
  shared with OpenGander. Keep DCR, RS256/JWKS, RFC 8414 metadata.
- **Postgres identity/auth store (D7).** Back the authz server with Postgres
  (local docker-compose for dev/test; prod in masques.ai). Sketch:
  - `users` (id, email, created_at, status)
  - `oauth_clients` (client_id, redirect_uris, grant_types — Dynamic Client Reg.)
  - `auth_grants` (code/PKCE, client_id, user_id, scopes, expiry)
  - `refresh_tokens` (token_hash, user_id, client_id, scopes, revoked_at) — revocation
  - `scopes` / `user_entitlements` (user_id, scope, source: free|subscription)
  - `reputation_*` (per-user namespace, v1.1 D6) — same DB, not a separate store
  - Signing keys for RS256 (or a managed KMS) feed the JWKS endpoint.
- OAuth identity = the per-user reputation namespace (v1.1 D6). Hosted exposes
  `reputation(...)`; **never `score`** (raw data stays local, D4).
- Deploy: mirror the OG Dockerfile + ALB `/health`; DNS `mcp.masques.ai`
  (resource) + `app.masques.ai` (authz); managed Postgres in the masques.ai domain.
- Free tier (no payment yet).

## Phase C — Monetization (DESIGN ONLY), in two rungs

**C1 — Subscription (OAuth + Stripe).** The starting model. Entitlements gate
hosted premium masques / reputation / analytics behind a Stripe subscription,
keyed on the Phase-B OAuth identity. **Reuses the OpenGander Stripe + OAuth
stack** (OG already has a Stripe webhook pipeline) — config + entitlements, not
net-new payment infra.

**C2 — Author-payout marketplace.** The evolution: masque authors paid per use.
Solana / TigerBeetle on masques.ai; credit-card/wallet ↔ subscription budget
**escrow** accounts; gate MCP tool calls (cleaner than escrow-on-don). Builds on
`docs/future/{roadmap,tigerbeetle-integration}.md`.

## Acceptance Criteria

### Phase A (BUILD)
- [ ] **M1** — A local FastMCP **stdio** server starts and a standard MCP client
  (MCP Inspector / Claude Desktop) lists its tools.
- [ ] **M2** — `list_masques` returns the full catalog (≥35 bundled), merging
  private `~/.masques` with bundled `personas/`, private taking precedence.
- [ ] **M3** — `inspect_masque("Firekeeper")` returns its lens, context,
  attributes, and rubric.
- [ ] **M4** — `don("Codesmith", intent?)` returns a composed identity block
  containing the masque's lens + context (the same content the plugin injects).
- [ ] **M5** — Each masque is exposed as an MCP prompt; `prompts/get` returns the
  composed identity.
- [ ] **M6** — `score` invokes the local judge and returns the two-layer reaction.
- [ ] **M7** — One authoritative compose: the Claude Code plugin shells out to the
  `masque` CLI (or the core), so plugin and MCP server cannot drift — verified by a
  parity check.
- [ ] **M8** — Docs show registering the local server in a real MCP client,
  verified against at least one.

### Phase B (DESIGN — acceptance for when built)
- [ ] **M9** — The hosted server validates an RS256 OAuth token via the authz
  server's JWKS and rejects unauthenticated/invalid/expired tokens with a 401
  carrying `WWW-Authenticate` + RFC 9728 `resource_metadata` (reusing
  `server.py`/`jwt_auth.py`).
- [ ] **M10** — Scope enforcement: a token without `masque:read` cannot call
  `list_masques`; `score` is absent from the hosted tool set (D4).

## Open Questions

1. **OQ1 — Authz server: share vs clone. RESOLVED (2026-06-01): clone.** Masques
   gets its own IdP at `app.masques.ai` (independent identity), backed by Postgres
   for users + scopes (D6/D7). Not sharing `app.opengander.io`.
2. **OQ2 — Session/attribution under MCP.** No ambient `CLAUDE_CODE_SESSION_ID`.
   Does `don` mint+return a session id, accept one from the client, or write local
   state? Drives how `score` attributes a session.
3. **OQ3 — Core/CLI vs plugin.** Phase A makes the plugin shell out to the `masque`
   CLI (M7). Confirm the plugin is allowed to depend on a local Python install, or
   ship a self-contained binary (e.g. `uv tool` / PyInstaller).
4. **OQ4 — Bundled-masque distribution.** How does a standalone server find
   `personas/` when not run from the repo? Vendor them into the package, or resolve
   via `MASQUES_HOME` / an env path.
5. **OQ5 — Persistence UX.** How loudly do we surface that `don` relies on the host
   keeping the identity in context (D5)? Per-client behavior varies.

## Scope Boundary — NOT doing in v1.2

- No hosted server, no HTTP transport, no OAuth in Phase A (Phase B, design-only).
- No payments, Solana/TigerBeetle, escrow, or 402/x402 (Phase C, deferred to
  `docs/future/`).
- No change to the masque schema or to existing personas.
- No removal of the Claude Code plugin — it becomes adapter #1 (shelling out to the
  shared core).
- No changes to OpenGander — we *reference and reuse its patterns*, we do not modify
  that repo.

## Appendix — concrete OpenGander references

- MCP resource server: `~/git/opengander/services/mcp-server/src/opengander_mcp/`
  (`server.py`, `jwt_auth.py`, `jwks.py`, `scopes.py`, `revocation.py`, `audit.py`,
  `tools/`), `pyproject.toml` (fastmcp≥2.14, PyJWT[crypto], httpx, cachetools,
  uvicorn), `Dockerfile`, `promptfoo/`.
- OAuth authorization server: `~/git/opengander/apps/web/src/app/oauth`,
  `apps/web/src/lib/oauth`, `apps/web/src/app/api/oauth`,
  `apps/web/src/app/.well-known/oauth-authorization-server`,
  `apps/web/src/app/api/.well-known/jwks.json`.
- Hosted today: `mcp.opengander.io` (resource), `app.opengander.io` (authz);
  Masques mirrors: `mcp.masques.ai`, `app.masques.ai` (or shared).
- Stripe: OpenGander commit "feat: add stripe webhook pipeline" — reuse for C1.
