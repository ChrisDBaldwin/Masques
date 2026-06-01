# Progress — PRD v1.2: Masques as an MCP Server

> Monotonic memory for the Phase A build (M1–M8) + Phase B/C design deepening.
> Source: docs/prd-v1.2-mcp-server.md · Epic: masques-zyu

## MORNING REPORT
_(written at exit)_

---

## Acceptance Criteria

### Phase A (BUILD)
- [x] **M1** — Local FastMCP stdio server starts; MCP client lists its tools. ✅ Inspector CLI + stdio.
- [x] **M2** — `list_masques` returns full catalog (≥35), private over bundled. ✅ 39 (35+4).
- [x] **M3** — `inspect_masque("Firekeeper")` returns lens/context/attributes/rubric. ✅ rubric 1534ch.
- [x] **M4** — `don("Codesmith", intent?)` returns composed identity block (lens+context). ✅ +Intent.
- [x] **M5** — Each masque exposed as MCP prompt; `prompts/get` returns composed identity. ✅ 39 prompts.
- [x] **M6** — `score` invokes local judge, returns two-layer reaction. ✅ status ok, Layer A+B.
- [ ] **M7** — One authoritative compose: plugin shells out to `masque` CLI; parity check.
- [ ] **M8** — Docs show registering local server in a real MCP client, verified.

### Phase B/C (DESIGN ONLY — deepen beads)
- [ ] **D-46z** — Postgres identity/auth store design notes
- [ ] **D-an2** — Clone OAuth authz → app.masques.ai design notes
- [ ] **D-og3** — Hosted resource server design notes
- [ ] **D-c3k** — Deploy design notes
- [ ] **D-ass** — Stripe subscription (C1) design notes
- [ ] **D-9n1** — Author payouts (C2) design notes

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
