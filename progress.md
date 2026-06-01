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
- [ ] **C2** — A never-donned `claude` session is captured to local JSONL with a detectable session boundary. Verify: query real logs.jsonl for baseline session.id.
- [ ] **C3** — Masque and baseline sessions both present, distinguishable by a `masque` field (null for baseline). Verify: DuckDB attribution query over real data + sidecar map.
- [x] **C4** — `/audience status` reports house open/closed + count of captured sessions. **VERIFIED** (Iter 2).

### Tier 2 — Honest scoring (Phase 2)
- [ ] **C5** — Each session assigned a `task_class` by heuristic; `unclassified` valid; baselines classify too. Verify: run classifier SQL over real data, paste class distribution.
- [ ] **C6** — Mid-stream masque switch flagged `attribution: mixed`, excluded from lift. Verify: SQL over a synthesized mixed session.
- [ ] **C7** — `/performance` emits Layer-A 7-point reaction for every scored session, from session one, no baseline required. Verify: run score.sql over real data, paste band.
- [ ] **C8** — When a task-class has sufficient baseline sessions, `/performance` adds Layer-B lift as a delta vs baseline; below threshold shows only Layer A. Verify: SQL lift query + threshold gate.
- [~] **C8b** — Rubric-bearing masque → Layer-A band from rubric read; rubric-less → activity fallback. **SCHEMA + example done (Iter 3)**; judge-interface wiring pending (score.sql rewrite).

### Tier 3 — Personal reputation (Phase 3) — DESIGN ONLY
- [ ] **C9** — Scores persist across sessions in a personal reputation corpus. (design + bead)
- [ ] **C10** — Per-(masque, task-class) lift figure w/ sample count retrievable across sessions. (design + bead)

### Tier 4 — Privacy contract (cross-cutting)
- [ ] **P1** — Nothing leaves the machine unless forwarding explicitly opted in. Verify: collector default pipeline is local-only; ClickHouse gated.
- [ ] **P2** — Forwarded payload contains only the Tier-2 derived signal (no prompts/tool I/O/code). Verify: document the contract + strip path.

### Tier 5 — Documentation reframe
- [ ] **P3** — `docs/vision.md`, `docs/evaluation.md`, `README` lead with measurable identity / persistent audience. Verify: close-read.
- [ ] **P4** — `docs/future/` retains payment/factory/marketplace vision, marked deferred. Verify: ls + close-read.

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
