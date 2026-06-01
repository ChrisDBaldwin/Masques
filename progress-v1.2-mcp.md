# Progress — PRD v1.2: Masques as an MCP Server

> Monotonic memory for the Phase A build (M1–M8) + Phase B/C design deepening.
> Source: docs/prd-v1.2-mcp-server.md · Epic: masques-zyu

## MORNING REPORT (2026-06-01)

**Phase A (M1–M8) is COMPLETE and VERIFIED. Phase B/C design beads carry buildable notes.**
Branch `prd-v1.2-mcp-server` pushed; `git status` clean. No PR opened (left for you).

### Done + verified (evidence in iteration log below)
- **One tool-agnostic core** (`services/mcp/`, package `masques_mcp`) + `masque` CLI — the single
  authoritative compose. `resolve` (private over bundled), `compose` (the `<masque-active>` block),
  `list`, `inspect`, `score` (local judge wrapper).
- **FastMCP stdio server** (`masques-mcp`): tools `list_masques`/`inspect_masque`/`don`/`doff`/`score`,
  39 `don-<name>` prompts, `masque://catalog` + `masque://{name}` resources.
- **M1** stdio server lists tools in MCP Inspector CLI **and** Claude Code (`✓ Connected`).
- **M2** 39 masques (35 bundled + 4 private), private precedence proven.
- **M3** `inspect_masque(Firekeeper)` → lens+context+attributes+rubric (1534-char rubric).
- **M4** `don(Codesmith, intent)` → identity block w/ Lens+Context+Intent.
- **M5** 39 prompts; `prompts/get don-firekeeper` → composed identity.
- **M6** `score` → local judge two-layer reaction (status ok, Layer A `great`, Layer B n/a baseline).
- **M7** plugin commands shell out to the CLI; parity test pins CLI == core == server (9 tests).
- **M8** `docs/mcp-server.md` + verified `claude mcp add masques` → `✓ Connected`.
- **30 tests pass** (10 core + 11 server + 9 parity).
- **Phase B/C** (46z, an2, og3, c3k, ass, 9n1): deepened `bd --design` notes — concrete OG file
  maps, Postgres DDL, retargeting deltas, M9/M10 hooks, Stripe webhook reuse, TigerBeetle escrow
  model. Left OPEN (design-only, not built).

### Blocked / not built (by design — Phase B/C is DESIGN ONLY per the PRD)
- None blocked. All Phase B/C work is intentionally design-only; no OAuth/Postgres/Stripe/Solana
  code was written, per scope. The six beads are design-ready for a future build.

### Single most important decision to review
**OQ3 — how the plugin invokes the CLI.** The commands now call `masque` on PATH (via
`uv tool install`) with a `uv run --project ${CLAUDE_PLUGIN_ROOT}/services/mcp` fallback. This
assumes the plugin may depend on a local Python/uv install. If you'd rather ship a self-contained
binary (PyInstaller / `uv tool`), that changes the install story in `commands/*.md` and
`docs/mcp-server.md`. Verified the `uv run` fallback works; the PATH path needs `uv tool install`.

### Suggested next first move
Decide OQ3 (above). If "local uv install is fine," Phase A is shippable as-is — review the diff and
merge. If not, the only change is the CLI-resolution snippet in the three command files + the doc.
Then Phase B is a clean fan-out from the `og3` design note (lift OG `server.py` auth scaffold onto
the existing `services/mcp/server.py`, gated by a `hosted` flag).

### Note on the live MCP registration
I registered `masques` in **your** Claude Code local config (`claude mcp add`) to verify M8. It
points at `uv run --project /Users/chris/git/masques/services/mcp masques-mcp` and is connected.
Remove with `claude mcp remove masques -s local` if you don't want it.

---

---

## Acceptance Criteria

### Phase A (BUILD)
- [x] **M1** — Local FastMCP stdio server starts; MCP client lists its tools. ✅ Inspector CLI + stdio.
- [x] **M2** — `list_masques` returns full catalog (≥35), private over bundled. ✅ 39 (35+4).
- [x] **M3** — `inspect_masque("Firekeeper")` returns lens/context/attributes/rubric. ✅ rubric 1534ch.
- [x] **M4** — `don("Codesmith", intent?)` returns composed identity block (lens+context). ✅ +Intent.
- [x] **M5** — Each masque exposed as MCP prompt; `prompts/get` returns composed identity. ✅ 39 prompts.
- [x] **M6** — `score` invokes local judge, returns two-layer reaction. ✅ status ok, Layer A+B.
- [x] **M7** — One authoritative compose: plugin shells out to `masque` CLI; parity check. ✅ 9/9 parity.
- [x] **M8** — Docs show registering local server in a real MCP client, verified. ✅ Claude Code ✓ Connected.

### Phase B/C (DESIGN ONLY — deepen beads)
- [x] **D-46z** — Postgres identity/auth store design notes (DDL, CH→PG divergence, revocation map, docker-compose)
- [x] **D-an2** — Clone OAuth authz → app.masques.ai design notes (per-file clone map, retargeting deltas)
- [x] **D-og3** — Hosted resource server design notes (verbatim lifts, score-absent, reputation() add, M9/M10)
- [x] **D-c3k** — Deploy design notes (Dockerfile/ALB mirror, DNS, env/config matrix, M9 invariant)
- [x] **D-ass** — Stripe subscription (C1) design notes (OG webhook reuse, entitlement toggle, free/paid split)
- [x] **D-9n1** — Author payouts (C2) design notes (TB escrow ledger, per-call metering hook, Solana vs TB)

---

## Iteration Log

### Iteration 0 — setup
- Branch `prd-v1.2-mcp-server` current; PRD read in full.
- Studied reuse target `~/git/opengander/services/mcp-server` (server.py, pyproject, tools/_common.py, tools/schema.py).
- Studied compose logic in `commands/don.md` (Step 4 `<masque-active>` block is the identity block).
- Tooling verified present: `uv`, `python3`, `node`/`npx`, `duckdb`.
- 35 bundled personas, 4 private masques.
- Created this progress file.

### Iteration 1 — masques-oru: tool-agnostic core + `masque` CLI (DONE)
Built `services/mcp/` (package `masques_mcp`, mirroring OG `services/mcp-server`):
- `core.py` — `resolve` (private `$MASQUES_HOME` over bundled `personas/`, case-insensitive,
  OQ4 path resolution), `compose` (+`build_identity_block` = the `<masque-active>` block don.md
  injects), `list_masques` (dedup by stem, private wins), `inspect`, `score` (shells `judge.sh`,
  degrades gracefully if duckdb/data absent).
- `cli.py` — `masque list|inspect|compose|score` (`--json` flag).
- `pyproject.toml` — fastmcp>=2.14 + PyYAML; scripts `masque` + `masques-mcp`.
- `tests/test_core.py` — 10 tests (spec for resolve/compose/list/inspect).

**Evidence:**
```
$ masque list --json | ... → total: 39  sources: {private:4, shared:35}
$ masque inspect Firekeeper → name Firekeeper v0.3.0 has_rubric True
    keys: name,version,source,path,lens,context,attributes,rubric,has_rubric,spinnerVerbs
$ masque compose Codesmith "ship the parser" → <masque-active name="Codesmith" version="0.2.0"> ... ## Lens ...
$ precedence: MASQUES_HOME shadow → Codesmith source:private version:9.9.9; list total stays 35
$ masque score → session …; layer_a: reaction great; layer_b: n/a (baseline)
$ pytest tests/test_core.py → 10 passed
```
Note: M2/M3/M4 satisfied at the CORE/CLI layer; will re-verify through the MCP server (b83) for M1–M4.
bd: masques-oru closed.

### Iteration 2 — masques-b83/0gg/vvw/nsn: FastMCP stdio server (DONE → M1–M6)
Built `server.py` (mirrors OG server.py minus ClickHouse/auth) + `session.py` (soft local
session state, D5-honest). All four server-wiring beads done together (they share server.py):
- **b83** tools: `list_masques`, `inspect_masque(name)`, `don(name,intent?)`, `doff()`.
- **0gg** prompts: one `don-<stem>` per masque (39), `prompts/get` → composed identity.
- **vvw** resources: `masque://catalog` + `masque://{name}` template.
- **nsn** `score(session_id?)` → `core.score` → `judge.sh`, LOCAL-ONLY (D4), degrades gracefully.
- `tests/test_server.py` — 11 client-level tests. Full suite: **21 passed**.

**Evidence (real stdio + canonical MCP Inspector CLI):**
```
$ npx @modelcontextprotocol/inspector --cli .venv/bin/masques-mcp --method tools/list
    → tools: [doff, don, inspect_masque, list_masques, score]            # M1
$ … --method prompts/list → prompt count: 39                            # M5
$ … --method tools/call --tool-name don --tool-arg name=Codesmith
    → name Codesmith 0.2.0; block: <masque-active name="Codesmith" version="0.2.0">  # M4
$ FastMCP Client (in-memory + StdioTransport):
    M2 list_masques count: 39
    M3 inspect Firekeeper: v0.3.0 has_rubric True rubric_len 1534
    M4 don Codesmith: Lens+Context+Intent present; doff: doffed
    M5 prompt don-firekeeper → <masque-active name="Firekeeper" version="0.3.0">
    M6 score status: ok; report head: session: 56626d73-…
    resource masque://catalog count 39; masque://Witness → Witness v0.2.0
```
bd: masques-b83, masques-0gg, masques-vvw, masques-nsn closed.

### Iteration 3 — masques-6sc/0mf: plugin adapter + parity (DONE → M7)
- **6sc**: rewrote `commands/{don,list,inspect}.md` to shell out to the `masque` CLI instead of
  re-deriving compose/list/inspect in prose. don.md Steps 2-4 collapse into `$MASQUE compose`
  (stdout injected verbatim) + `--json` for session/spinner fields; list.md uses `$MASQUE list
  --json`; inspect.md uses `$MASQUE inspect --json`. CLI located via `masque` on PATH (uv tool
  install) or `uv run --project ${CLAUDE_PLUGIN_ROOT}/services/mcp masque` fallback (OQ3 documented).
- **0mf**: `tests/test_parity.py` proves byte-identical compose across all three adapters —
  CLI subprocess == `core.compose` == MCP server `don` tool — for Codesmith/Firekeeper/Mirror/
  Witness, with and without intent (9 tests). Plugin == CLI by construction (commands inject CLI
  stdout verbatim); this pins CLI == core == server, closing the chain.

**Evidence:**
```
$ pytest services/mcp/tests → 30 passed (10 core + 11 server + 9 parity)
$ CLAUDE_PLUGIN_ROOT=… uv run --project services/mcp masque compose Codesmith "demo"
    → <masque-active name="Codesmith" version="0.2.0"> ... (the plugin's actual fallback path works)
```
bd: masques-6sc, masques-0mf closed.

### Iteration 4 — masques-emq: docs + real-client registration (DONE → M8)
- Wrote `docs/mcp-server.md`: what the server exposes, install (`uv venv && uv pip install -e .`),
  register in Claude Code / Claude Desktop / Cursor / MCP Inspector, env config matrix, D4/D5 notes.
- **Verified against a real client (Claude Code):**
```
$ claude mcp add masques -- uv run --project /Users/chris/git/masques/services/mcp masques-mcp
$ claude mcp list → masques: uv run --project … masques-mcp - ✓ Connected
$ claude mcp get masques → Type: stdio · Status: ✓ Connected
```
(Also re-confirmed via MCP Inspector CLI in Iteration 2.)
bd: masques-emq closed. **Phase A (M1–M8) COMPLETE & VERIFIED.**
