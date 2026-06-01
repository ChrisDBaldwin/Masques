# Progress — PRD v1.1: The Persistent Audience

Branch: `prd-v1.1-persistent-audience` (off `mvp`). North star: `docs/prd-v1.1-persistent-audience.md`.
Source of truth for acceptance: PRD §Acceptance Criteria (C1–C10, P1–P4, C8b).
(Previous v1.0 log archived at `docs/progress-v1.0.md`.)

> **Grounding rule:** a box is checked ONLY after running its stated verification
> method and pasting real evidence into the iteration log below. No checks on faith.

---

## MORNING REPORT
_(written at exit — see bottom of file until then)_

---

## Acceptance Criteria

### Tier 1 — Always-on capture (Phase 1)
- [x] **C1** — Collector runs always-on (`restart: unless-stopped`), survives reboot, no per-session start. **VERIFIED** (Iter 1).
- [x] **C2** — A never-donned `claude` session is captured to local JSONL with a detectable session boundary. **VERIFIED** (Iter 4).
- [x] **C3** — Masque and baseline sessions both present, distinguishable by a `masque` field (null for baseline). **VERIFIED** (Iter 4).
- [x] **C4** — `/audience status` reports house open/closed + count of captured sessions. **VERIFIED** (Iter 2).

### Tier 2 — Honest scoring (Phase 2)
- [x] **C5** — Each session assigned a `task_class` by heuristic; `unclassified` valid; baselines classify too. Verify: run classifier SQL over real data, paste class distribution.
- [x] **C6** — Mid-stream masque switch flagged `attribution: mixed`, excluded from lift. Verify: SQL over a synthesized mixed session.
- [x] **C7** — `/performance` emits Layer-A 7-point reaction for every scored session, from session one, no baseline required. Verify: run score.sql over real data, paste band.
- [x] **C8** — When a task-class has sufficient baseline sessions, `/performance` adds Layer-B lift as a delta vs baseline; below threshold shows only Layer A. Verify: SQL lift query + threshold gate.
- [x] **C8b** — Rubric-bearing masque → Layer-A band from rubric read; rubric-less → activity fallback. **VERIFIED** (schema+example Iter 3; judge interface Iter 4).

### Tier 3 — Personal reputation (Phase 3) — DESIGN ONLY
- [ ] **C9** — Scores persist across sessions in a personal reputation corpus. (design + bead)
- [ ] **C10** — Per-(masque, task-class) lift figure w/ sample count retrievable across sessions. (design + bead)

### Tier 4 — Privacy contract (cross-cutting)
- [x] **P1** — Nothing leaves the machine unless forwarding explicitly opted in. Verify: collector default pipeline is local-only; ClickHouse gated.
- [x] **P2** — Forwarded payload contains only the Tier-2 derived signal (no prompts/tool I/O/code). Verify: document the contract + strip path.

### Tier 5 — Documentation reframe
- [x] **P3** — `docs/vision.md`, `docs/evaluation.md`, `README` lead with measurable identity / persistent audience. Verify: close-read.
- [x] **P4** — `docs/future/` retains payment/factory/marketplace vision, marked deferred. Verify: ls + close-read.

---

## Iteration Log

### Iteration 0 — Setup & recon (2026-05-31/06-01)
- Branch `prd-v1.1-persistent-audience` created off `mvp`; PRD committed (`e307b08`).
- Beads already seeded: epic `masques-ir8` + children `ir8.1`–`ir8.13`, plus `masques-hxr` (masque-context OTEL hook), `masques-cpp` (Witness trace analyzer).
- Tooling confirmed present: `duckdb v1.4.4`, `docker`, `promptfoo`.
- **Real telemetry exists**: `services/collector/data/logs.jsonl` (21MB), `metrics.jsonl` (8MB). Event types: api_request (5954), tool_result (5219), tool_decision (5040), user_prompt (238), api_error (23). Many distinct `session.id`s — good dogfood corpus.
- **CRITICAL FINDING — collector is crash-looping.** `docker logs masques-audience`: the ClickHouse exporter (`ironwood:8123`, from `.env`) is unreachable; `create_schema: true` makes it a hard startup dependency, so the whole collector refuses to start — taking the local file sink down with it. This directly defeats "always-on" (C1). Per PRD (D1/D3, OQ1), ClickHouse is Tier-3/masques.ai and strictly opt-in; the local collector must be **local-only by default**. Fix is in scope for Phase 1.
- **Attribution reality (C3):** telemetry has NO masque field. Resource attrs are only host/os/service. Sessions keyed by `session.id`. Prompts ARE captured locally (`prompt` attr on user_prompt) — fine locally, must be stripped before any forwarding (D3/P2). Masque tagging needs a mechanism → sidecar session→masque map joined by the judge (bead `masques-hxr` for the richer OTEL-resource-attribute path).

### Iteration 1 — C1: always-on collector appliance (bead masques-ir8.1)
- **Root-cause fix.** Removed the ClickHouse exporter from the default pipelines in `services/collector/config.yaml` — it is now a documented opt-in (Tier-3/Phase-4). This kills the crash-loop: the local file sink no longer depends on an unreachable remote. (Also satisfies P1's local-default posture.)
- **Healthcheck mechanism.** The otel-contrib image is distroless (verified: no `sh`/`wget`/`curl`). Added a static `busybox:1.36-musl` binary to the image (`Dockerfile`, multi-stage `--from=probe`) purely so a Docker healthcheck can probe `:13133`. Added `healthcheck:` to `docker-compose.yml`: `busybox wget --spider http://127.0.0.1:13133/`, interval 30s, retries 3 → a HUNG collector goes unhealthy and `restart: unless-stopped` recovers it (not just a dead process).
- **Verification (real, live):**
  - `docker compose config` → passes (syntax valid).
  - `docker compose up -d --build` → built + started.
  - `docker ps` → `Up (healthy)`. Manual `curl http://localhost:13133/` → `HTTP 200`.
  - `docker inspect` → `RestartCount=0 Health=healthy Running=true`; last healthcheck exec `exit=0` (busybox probe genuinely runs in-container).
  - `docker logs` → no ClickHouse errors; pipelines started; debug exporter actively shows live tool_result events from THIS session (dogfooding — Claude Code OTEL env is configured and flowing to the local sink).
- **"Survives reboot" caveat (honest):** guaranteed by `restart: unless-stopped` + Docker-Desktop-start-on-login; I cannot physically reboot mid-session to prove it. Mechanism is correct and standard; documented in otel-setup. Not claiming an observed reboot.

### Iteration 2 — C4 + /audience seat-once rewrite (bead masques-ir8.2)
- **`commands/audience.md` rewritten** from per-session summon (`start`/`stop`/`config`) to seat-once lifecycle: `seat` (open the house once: `docker compose up -d --build`, verify `:13133` health, verify Claude Code OTEL env in `~/.claude/settings.json`, remind to enable Docker start-on-login), `dismiss` (close the house entirely), `status` (open/closed + captured session count + env), `logs`. `start`/`stop` kept as deprecated aliases so cross-command refs don't break. Folded the old `config` env block into `seat`.
- **`services/judge/captured.sh`** added — counts distinct `session.id` in the local JSONL (masque + baseline). Exit codes: 0 ok, 2 duckdb-missing, 3 no-data, so `/audience status` can degrade gracefully.
- **Verification (real, live):** ran the exact `status` action commands against the running collector:
  - `docker ps … {{.Status}}` → `Up 3 minutes (healthy)` (house OPEN).
  - `curl :13133/` → `200`.
  - `./services/judge/captured.sh` → `68`, exit 0 (68 sessions in the real corpus).
- **Cross-command trace:** audience.md references only existing paths (`services/judge/captured.sh`, `services/collector/data/logs.jsonl`, `docs/otel-setup.md`). The OTEL env block matches the keys actually present in the captured telemetry.

### Iteration 3 — `rubric` schema field + codesmith example (bead masques-ir8.4)
- **`schemas/masque.schema.yaml`:** added optional `rubric` (string) property — the measurable shadow of the lens, prose-first like lens/context. Only schema addition per PRD scope (no other churn).
- **`personas/codesmith.masque.yaml`:** added a `rubric` derived from codesmith's existing lens ("every line should teach"). **Pure addition** — `git diff` shows 16 insertions, 0 removals; lens/context untouched (honors the "don't modify persona content" constraint).
- **Verification (real, venv `/tmp/mvenv` with jsonschema 4.26 + pyyaml):**
  - `Draft202012Validator.check_schema` → schema valid after the addition.
  - codesmith → VALID, rubric=True (rubric-bearing case).
  - firekeeper, mirror → VALID, rubric=False (rubric-less controls).
  - Full corpus: all **35** personas still valid — the optional field broke nothing.
- C8b is partially met: the schema + worked example + a rubric-bearing/rubric-less pair exist and validate. The remaining half (a judge that actually emits a band from the rubric vs the activity fallback) is wired in the score.sql/judge iteration.

### Iteration 4 — Two-layer scoring engine: sessions.sql + score.sql + judge.sh (beads ir8.5/ir8.6/ir8.7; C2,C3,C5,C6,C7,C8,C8b)
The core of the product. Rewrote the judge from a single-masque 5-proxy verdict to the two-layer model over EVERY session.

**`services/judge/sessions.sql` (rewrite):** enumerates all 68 sessions; per-session boundaries, tool-mix (tool_result only — `tool_name` also appears on tool_decision), api cost/tokens, friction. Heuristic `task_class` (D5, coarse/first-match/tunable-OQ2): research→review→ops→debug→greenfield→refactor→unclassified. Masque attribution via LEFT JOIN to an `attribution` table (sidecar map): 0 masques=baseline, 1=clean, >1=mixed (D2). Fixed `attr` macro to also read OTLP `doubleValue` (cost_usd is a double — was silently zeroing cost).

**`services/judge/score.sql` (rewrite):** scores one target session. Layer A = 7-point band from an activity composite (0.35 success + 0.20 throughput + 0.20 cost + 0.25 low-friction) → perfect/great/good/neutral/bad/awful/detracting; OR a rubric band when an LLM/Witness judge supplies `rubric_band` (judge: rubric vs activity-fallback) — the D7 judge INTERFACE. Layer B = failed-tool-call lift vs the user's baseline corpus for the same task_class, GATED on baseline_min + clean attribution; otherwise honest `not_yet`/`n/a (baseline)`/`excluded (mixed)`. Old 5 proxies demoted to `supporting_signals`.

**`services/judge/judge.sh` (rewrite):** builds the attribution table from the optional sidecar `services/collector/data/sessions.attribution.jsonl` (empty → all baseline), passes target_session/rubric_band/baseline_min, runs both SQL files.

**`commands/don.md` (Step 5a added):** `/don` now appends `{session_id,masque,donned_at}` to the sidecar using `$CLAUDE_CODE_SESSION_ID` — which I verified equals the telemetry `session.id` (env value `7c8f7b8b…` → 205 matching events). This is the C3 capture mechanism, no OTEL plumbing needed. Append (not overwrite) so a second don in one session → `mixed`.

**Verification (all real `logs.jsonl`, 68 sessions):**
- **C5** task_class over all 68: refactor 18 / review 18 / unclassified 16 / ops 7 / greenfield 5 / debug 3 / research 1. total=classed=68 (every session classified; unclassified valid; all-baseline corpus still classifies). 
- **C7** Layer-A band for all 68: perfect 21 / great 32 / good 11 / bad 3 / awful 1; **0 null bands** — a reaction from session one, spans the scale both ways.
- **C2** baseline boundary: e.g. d204fe6f → baseline, 34.2 min, 4 prompts, 198 tools (don_time/doff_time present).
- **C3** end-to-end on real data via the env-var→sidecar→judge chain: my live session (`$CLAUDE_CODE_SESSION_ID`) with an attribution line → `masque: Codesmith, attribution: clean`; a no-line session → `masque: null (baseline)`. Distinguishable by the masque field, null for baseline.
- **C8** lift SHOWN: clean Codesmith refactor session vs baseline refactor corpus → `failed_tool_calls_lift_pct: +34.3` (15 baseline / 3 masque sessions, baseline_min=5). Threshold gate: same session with baseline_min=20 → `not_yet, baseline_sessions: 15 / 20 needed` (no misleading number).
- **C6** mixed: a session with two distinct masque lines → `attribution: mixed`, `masque: null`, Layer B `excluded (mixed attribution — PRD D2)`.
- **C8b** judge interface: `RUBRIC_BAND=perfect` → `reaction: perfect, judge: rubric` (activity_band still shown as `great` for transparency); no rubric → `judge: activity-fallback`. Combined with Iter-3 schema+codesmith rubric, both the rubric-bearing and rubric-less paths are exercised.
- **cost fix** confirmed: session d204fe6f now `cost_usd: 9.50`, `cost_per_tool: 0.0489` (was 0.00 before the doubleValue fix).

**Judgment call (flagged for review):** the task_class thresholds and the Layer-A activity weights/band cutoffs are first-pass and admittedly arbitrary (OQ2/OQ3). They are deliberately transparent and centralized so they can be tuned; correctness of the buckets is explicitly out of scope for v1.1 (the criteria require *a* class + *a* band for every session, which holds). Synthetic attribution was used ONLY to exercise C6/C8 mechanics (no masque sessions exist in the real corpus yet); C2/C3/C5/C7 used the real corpus unmodified.

### Iteration 5 — /performance two-layer rewrite (bead masques-ir8.8)
- **`commands/performance.md` rewritten** to surface Layer A always and Layer B only when `layer_b.status: shown`; otherwise print the honest one-line reason (`not_yet` / `n/a (baseline)` / `excluded (mixed)`) — never a fabricated number. Old 5 proxies reframed as a subordinate `supporting_signals` line. Documents the rubric-judge knob (`RUBRIC_BAND`) and `BASELINE_MIN`. Leads with the 7-point reaction.
- **Verification (field-name trace, end to end):** ran the spec's exact Step-3 command `TARGET_SESSION="$CLAUDE_CODE_SESSION_ID" judge.sh`; every YAML key the spec tells the model to read (`layer_a.{reaction,judge,activity_band,activity_score}`, `layer_b.status`, `supporting_signals.*`, `tool_mix`, `attribution`, `task_class`) is present in the real output. Live result: this session scored `good` (6.04) — the composite dropped from `great` earlier as the session grew to 570 min / 66 tools / $7.36 / 1.12 tools per min, i.e. scoring tracks reality.

### Iteration 6 — Documentation reframe (beads ir8.3, ir8.9; P3, P4)
- **`docs/otel-setup.md` (ir8.3)** rewritten around seat-once always-on: why always-on, privacy posture (local-only default), seat-once Step 1–2, the sidecar attribution mechanism, two-layer scoring pointer, deferred no-Docker/forwarding. Removed the old per-session `docker run` / "use /audience start" framing.
- **`docs/evaluation.md` (ir8.9)** rewritten to the two-layer rubric model: Layer A (rubric judge or activity fallback, 7-point), Layer B (lift, gated), clean-attribution-without-factory, task-class, judge-is-a-role, proxies demoted, real output example, Phase-3 persistence note. Leads with "Measurable Identity."
- **P3** — `README.md` now leads with a "Measurable Identity — the differentiated half" section (audience always seated, 7-point reaction + lift); reframed the Services tables from "optional telemetry" to "the audience that measures it, local by default"; replaced the stale 5-dimension judge section with the two-layer model. `docs/vision.md` gains a top "The Thesis: Observability Is the Core" section. `docs/evaluation.md` leads with measurable identity. **Verified by close-read + grep:** no stale `/audience start|stop` or "5 dimensions / keep-review-doff" framing remains in README/docs/commands (the only matches are inside the PRD, which is correctly describing the OLD state it replaces). All cross-reference targets exist.
- **P4** — `docs/future/` retains `roadmap.md` (agent-factory pivot) + `tigerbeetle-integration.md` (payments) + a `README.md` that explicitly marks them deferred and distinct from the shipping product. No change needed; verified by ls + close-read. (Left intact per scope: do not revive.)

**Judgment call (flagged for review):** the README/vision reframe pushes "observability is the core" to the top, which is a tonal shift from the very recent mvp commit `c7c2d7b` ("reframe around the minimal representation tool"). I kept the zero-infra don/doff truth intact and framed the audience as the *differentiated* half rather than replacing the representation framing — but this is the one place the PRD's thesis and the mvp positioning pull against each other. Worth a glance to confirm the balance is right.

### Iteration 7 — Privacy contract P1/P2 (cross-cutting)
- **P1 — nothing leaves unless opted in. VERIFIED.** Source `config.yaml` pipelines export only `[debug, file/*]` — no clickhouse. Running collector logs (filtering out the debug exporter's echo of my own session's tool text) show only local debug+file exporters, no clickhouse component, no connection errors. `docker exec masques-audience busybox netstat -tn` → **no outbound connections to :8123/:9000**. Forwarding requires explicitly uncommenting the clickhouse exporter (opt-in). Note: an earlier grep falsely "found remote attempts" — that was the debug exporter echoing my bash commands (which contained the strings "clickhouse"/"8123"), not real egress; disproved by netstat + the precise log filter.
- **P2 — forwarded payload is only the derived signal. VERIFIED at contract level.** The only candidate payload is the judge's YAML output; scanned it — keys are session/masque/attribution/task_class/duration + layer_a/b bands & numbers + supporting_signals (counts/cost) + tool_mix (counts). **No prompts, file paths, code, or tool I/O.** The local raw JSONL *does* contain rich content (confirmed: my session's `tool_parameters` capture full bash commands w/ paths) — and it is wired to NO remote, which is the guarantee. Caveat: an actual forwarder is not built (Phase 4 / bead ir8.12); the live end-to-end strip+forward verification belongs there. What is provable now — derived signal is content-free, raw content never leaves — holds.
