# PRD: Masques v1.1 — The Persistent Audience

**Project:** /Users/chris/git/masques
**Author:** Chris Baldwin + Claude
**Date:** 2026-05-31
**Status:** Draft for review
**Loop Mode:** Phased — design-heavy early, recursive-convergent late

---

## Problem Statement

Masques is "AssumeRole for Agents" — don a cognitive identity, work, doff. The
representation layer works. But the **interesting** half of the product — an
audience that watches a masque perform and tells you whether the costume
actually made the work better — has been left as plumbing.

What exists today:

- **`/audience`** is a Docker wrapper: `start` / `stop` / `status` / `config` /
  `logs`. It manages a container. It contains zero insight. The line "the
  audience sees everything, the full show" is aspiration, not behavior.
- **`/performance`** runs `services/judge/score.sql` once, on demand, and prints
  a bar chart of five dimensions: tool-success rate, tools-per-prompt,
  tools-per-minute, cache-hit ratio, cost-per-tool.

The five dimensions share one fatal flaw: **they are masque-agnostic.** They
produce the identical score whether you donned Codesmith, donned Firekeeper, or
donned nothing at all. They measure agent *activity*, never masque *value*. A
masque that makes the agent flail through five tool calls per prompt scores
*higher* on "autonomy." Codesmith's promise is "every line should teach" — the
audience never checks whether a single line taught anything. It counts how often
a tool returned `success: true`.

Three compounding failures:

1. **Wrong target.** Metrics measure activity proxies, not masque-attributable
   outcome. The one question that makes masques interesting — *did the costume
   help?* — is never asked.
2. **Unreachable.** Scoring is gated behind Docker + ClickHouse + OTEL env config
   + a DuckDB install + a manual `/audience start`. The audience is never in the
   house. An insight nobody turns on is not a force.
3. **Hollow verdict.** `keep / review / doff` is computed from those proxies, so
   the one product-shaped output is built on sand. The docs even ship the
   disclaimer: *"best-effort based on the OTLP JSON spec. If scores look wrong,
   the JSONL structure may differ."*

**Success looks like:** the audience is *always seated*. Every session — masque
or baseline — is captured by default, with no per-session ritual (the collector is
seated once and left running). Over time the record answers, honestly: *"Codesmith
runs +1.4 over your no-masque baseline on Zig refactor work."* Measurable identity. That is the differentiated product,
and it is the part that has been ignored.

### The thesis

> **Observability is the core of the product.** A masque without an audience is
> just a system prompt. The value is the *watching* — giving the person who wears
> a masque honest evidence about how it performed *for them*, on *their* work.

This is a deliberately modest, personal claim. We are **not** claiming to advance
representation engineering or to out-measure a frontier lab — the state of the art
there is almost certainly ahead of this project. The claim is narrower and
attainable: *your* audience tells *you* whether *this* costume helped *your*
sessions. The honesty comes from the audience never leaving, not from a universal
benchmark.

### Audience

- **Primary:** Chris (author) — wants the insight layer to become the spine of
  the product, attainable now without the deferred marketplace.
- **Secondary:** Masques users — want to know, with evidence, which masques
  actually help their work.

### Constraints

- The `mvp` branch deliberately cut payments/factory/marketplace
  (commit `c89647e`). This PRD does **not** revive them.
- Plugin remains markdown command specs — no MCP server required for v1.1.
- Local scoring runs on a single always-on local collector (Docker, seated once) —
  no remote dependency. The masques.ai server is strictly opt-in. A fully
  zero-infra local path is a deferred improvement (OQ1), not a v1.1 requirement.
- Privacy is the adoption gate: raw prompts, tool I/O, and code must never leave
  the user's machine.
- Must not break the TUI, the existing personas, or the don/doff loop.

### Scope Boundary — What We Are NOT Doing

- **Payments** — TigerBeetle, Solana, escrow, 402 gating. Stays in `docs/future/`.
- **Agent-factory rewrite** — process-boundary spawn-at-turn-0 model. Stays in
  `docs/future/roadmap.md`. (See "Clean attribution without the factory" below
  for how v1.1 gets honest measurement without it.)
- **Marketplace / reputation-for-sale** — no public masque ranking economy.
- **Global community reputation in v1.1** — designed for, but the global pool is
  a later phase. v1.1 ships *personal* reputation.
- **Broad schema churn** to `masque.schema.yaml`. The one intended addition is the
  optional `rubric` field (D7) — a masque declaring how to know it worked. A
  `task-class` hint remains an open question; no other schema changes.
- **The legacy ClickHouse migrations** for the old payment ledger.

---

## The Reframe: Three Tiers

The current design has two databases (DuckDB local, ClickHouse remote). The
missing middle is the part that makes it a product: **the data contract that
crosses the boundary.**

| Tier | Lives | Answers | State |
|------|-------|---------|-------|
| **1. Session score** | Local (DuckDB) | "How did *this* session go?" | Ephemeral |
| **2. The audience signal** | The wire | "What crosses the boundary — and what never does?" | The contract |
| **3. Reputation** | masques.ai (ClickHouse) | "Does this masque beat baseline?" | Persistent |

Moving ClickHouse to a server does **not**, by itself, fix the insight problem.
A server full of activity proxies is reputation theater at scale. The signal is
the product; the server is delivery. Tier 1 and Tier 2 carry the weight.

---

## Key Design Decisions

Resolved during design (2026-05-31). Each shapes the build.

### D1 — The audience is always seated

The single keystone. You cannot A/B or baseline against a thing you summon. The
quantifiable side only becomes reachable when capture is **ambient and
unconditional** — every session watched, masque or not.

This collapses two failures into one fix:

- **Unreachable → always-on.** Capture is seated by default, not
  `docker compose up`-on-demand.
- **No counterfactual → emergent baseline.** "Baseline-Claude" is simply *the
  corpus of sessions where no masque was donned*. Lift falls out of the ambient
  record. Observational, not a lab RCT — but honest, and it only exists because
  the audience never left.

**Always-on is the requirement; zero-infra is not.** These are separate
properties — v1.1 keeps the first and defers the second. What is incompatible with
always-on is **Docker-*on-demand*** — today's `/audience start` summoned once per
session. **Docker-*always-on*** — the existing OTEL collector run as a persistent
container (`restart: unless-stopped`), seated once and left running — is perfectly
compatible, and it is the **v1.1 mechanism (OQ1, resolved)**. The audience is
seated by leaving the house open, not by rebuilding the house.

A **no-Docker, zero-infra** capture path (a native OTLP receiver, a launchd/login
service, or a direct OTEL file sink) is a real friction improvement — but it is
**standalone, deferred work on the cybernetic loop, not a v1.1 blocker.** The only
thing that stays strictly *optional* in v1.1 is forwarding to masques.ai
(Tier 3); the local always-on collector is the default setup.

### D2 — Clean attribution without the factory

`docs/future/roadmap.md` already identified that reputation needs **clean
attribution**, and proposed a heavy fix: rebuild masques as an agent factory so
each masque is a turn-0 subprocess. v1.1 reaches clean-*enough* attribution
without that rewrite.

The roadmap's contamination concern is real but narrow: it bites on *mid-session
don/doff* (doff leaves the lens in context, poisoning a post-doff "baseline").
At the **session grain** — each `claude` invocation is already a process — the
problem dissolves:

- A session that **never donned** = a clean baseline sample.
- A session that **donned once, early** = a clean masque sample.
- The thing to avoid is *switching masques mid-session*.

So v1.1's honest-measurement rule is **"one masque per scored session."** This is
not a constraint imposed on users — it is *how masques are already used in
practice*: spawn a fresh agent, don a masque immediately, hand it a prompt to chew
on. The session **is** the masque for its lifetime. v1.1 simply scores at that
natural grain.

A session that switches masques mid-stream is flagged `attribution: mixed` and
excluded from lift computation (still scored for the user's own curiosity).
Measuring contamination deliberately — what *does* leak across a doff? — is a
genuinely interesting experiment, but it is **deferred, not v1.1.** This is a
measurement-hygiene discipline, not a reason to rebuild everything — the bridge
from today's in-session model to trustworthy reputation, at no factory cost.

### D3 — The data contract: derived scores + work metadata, never content

Score locally; ship only numbers and coarse tags. What may cross to masques.ai:

```yaml
# The audience signal — the ONLY thing that leaves the machine
masque: Codesmith            # null for baseline sessions
version: "1.2.0"
task_class: refactor         # heuristic-inferred (see D5)
dimensions: { ... }          # the redesigned scores (see D4)
baseline_delta: +1.4         # lift vs this user's baseline corpus, if computable
metadata:
  languages: [zig, english]  # programming + human language detected
  tool_profile: [Edit, Bash, Grep]   # which tools/MCP servers were invoked
  mcp_servers: [gitnexus]
  response_time_ms_p50: 4200
  duration_min: 38
  attribution: clean         # clean | mixed
```

Never leaves: prompts, file contents, tool inputs/outputs, code, secrets. The
sensitive work happens on-device in DuckDB; the server only ever sees the
derived signal. This is the privacy contract that makes opt-in forwarding
trustworthy.

### D4 — Two layers: an immediate reaction, and lift that earns itself

Lift vs. baseline is the honest comparative verdict — but it cannot exist on
session one, before any baseline corpus has accrued. Forcing the user to wait for
"enough data" before the audience says anything is the cold-start trap. So scoring
has two layers.

**Layer A — The house reaction (available from session one).** A single
qualitative verdict on a 7-point scale, oriented positive or negative from the
very first session, like a Dark Souls soapstone rating:

> **perfect · great · good · neutral · bad · awful · detracting**

This is an *absolute* read of how the session went, derived from observable
session signals (tool success, completion, throughput, cost, friction). Those
activity signals — the ones today's `/performance` misuses as if they were
masque-attribution — find their honest home here: they answer *"how did this
go?"*, never *"did the masque cause it?"* The reaction is immediate, oriented, and
never pretends to be a controlled comparison. The audience always has *something*
to say.

**Layer B — Lift (emerges as the corpus thickens).** Once enough same-task-class
sessions exist, the audience layers on the comparative verdict: **relative lift
vs. the user's baseline corpus** — "Codesmith completes Zig refactor work with 22%
fewer failed tool calls than your baseline." This is the masque-attribution layer,
and it is a *difference*, never an absolute level. Below the baseline threshold,
only Layer A shows; Layer B announces itself when it has earned the right to.

For masques that carry a **rubric** (D7), the Layer-A band comes from a
qualitative read against that rubric — via an LLM judge, optionally a persistently
running Witness-masque agent (D7) — with the activity signals as supporting
context. Masques without a rubric, or sessions with no judge configured, fall back
to an activity-only band. Either way the qualitative signal feeds Layer A rather than
living in a separate, ignored command. The signal→band mapping for Layer A and the
lift dimensions for Layer B are Phase 2 deliverables.

### D5 — Task-class is heuristic-inferred

Lift is only honest when comparing *the same kind of work*. Task-class is the
bucket. It is **inferred from signals the always-on audience already sees** —
tool mix, files touched, language, edit-vs-read ratio, session shape — so it
works for **all** sessions, including baselines that never ran `/don` and so have
no declared intent. Fuzzier than self-declaration, but universal. Starter
buckets: `refactor`, `debug`, `greenfield`, `review`, `research`, `ops`,
`unclassified`. The classifier is a deliverable of Phase 2; v1.1 may begin with a
single global bucket and refine.

### D6 — Reputation is personal first, global opt-in later

masques.ai stores **your** scores across **your** sessions and machines first —
"Codesmith works for me on Zig refactors." Honest, no anti-gaming needed,
attainable soon. A later phase adds an opt-in anonymized community pool, at which
point identity, normalization across users, and anti-gaming get designed in. The
personal store may begin as persistent local DuckDB and graduate to a per-user
masques.ai namespace.

### D7 — Each masque carries its own rubric, authored at creation

`services/judge/score.sql` is one-dimensional *by nature*: SQL over telemetry can
only ever measure **generic activity** — tool success, throughput, cost. It cannot
know that a great Codesmith session is one where *every line teaches*, or that a
great Firekeeper session is one where the incident was contained without panic.
Those are masque-specific definitions of "good," and none of them live in the
telemetry. Forking `score.sql` into one query per masque would just be N
contortions of a tool that is blind to the thing you actually want to measure.

The right fix is the one the masque already implies: **the masque declares what
its own success looks like.** A masque's lens says *how to think and what to
refuse*; the **rubric** is the measurable shadow of that lens — *how to know it
worked*. The author who writes the lens is the one person who knows, so they
author the rubric alongside it, in the YAML next to `lens` and `context`:

    rubric: |
      A great session leaves code that teaches: comments explain *why* not
      *what*, names are self-documenting, a newcomer could trace the change
      unaided. It fails if it ships cleverness over clarity, or silent magic.

This makes the verdict **qualitative and masque-specific**: a judge reads the
session against the rubric and assigns the Layer-A band (D4). **The judge is a
role, not a fixed component.** DuckDB cannot read freeform prose, so it only ever
produces the activity *fallback* band — rubric-aware judging needs an LLM judge.
That judge can be an ad-hoc scoring pass, or, optionally, a **persistently running
agent that has donned the Witness masque** — an attentive critic in the audience
rather than a dumb meter. Witness is *a* judge, not *the* judge: an optional way
to upgrade scoring from mechanical to qualitative. The generic `score.sql` is
*demoted* from "the verdict" to a **supporting signal** (cost, throughput,
friction), never the verdict itself.

**Cold-start fallback.** A masque with no authored rubric still gets a Layer-A
band from the generic activity signal — the simple positive/negative the audience
can always produce. Rubric-bearing masques get a *meaningful* band. v1.1 can ship
the generic reaction first and light up rubric-judging as masques gain rubrics.

**Authoring flow.** Because the rubric derives from the lens, the masque-creation
flow can *propose a draft rubric from the lens* for the author to refine — "built
alongside the masque," not bolted on after.

**Trust note.** A self-authored rubric is fine for *personal* reputation (you only
compare your own sessions). For the global pool (Phase 4) it is gameable — an
author could write a flattering rubric — so global reputation will need normalized
or reviewed rubrics. Personal-first sidesteps this; the global phase inherits it
(see OQ7).

---

## Architecture

```
                    ┌──────────────────────────────────────────┐
                    │  Every claude session (masque OR baseline)│
                    └─────────────────────┬────────────────────┘
                                          │ OTEL logs/metrics (always on)
                                          ▼
   TIER 1 ┌──────────────────────────────────────────────────┐
   local  │  Persistent local audience  (always-on)           │
   default│  OTEL collector, restart: unless-stopped          │
          │  seated ONCE, survives reboot → local JSONL       │
          │  (no-Docker zero-infra path = deferred, OQ1)      │
          └─────────────────────┬────────────────────────────┘
                                │ tail
                                ▼
          ┌──────────────────────────────────────────────────┐
          │  The judge (a role, not one component — D7)        │
          │                                                    │
          │  DuckDB (ambient, always-on, mechanical):          │
          │   - classify task-class (heuristic, D5)            │
          │   - one-masque-per-session hygiene (D2)            │
          │   - activity fallback band (D4 Layer A)            │
          │   - lift vs baseline (D4 Layer B)                  │
          │   - persist personal reputation corpus (D6)        │
          │                                                    │
          │  Witness-masque agent (OPTIONAL, qualitative):     │
          │   - reads session vs the masque's rubric (D7)      │
          │   - upgrades the Layer-A band from meter → critic  │
          └─────────────────────┬────────────────────────────┘
                                │  derived signal ONLY (D3)
   TIER 2 ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─│─ ─ ─ ─ the wire / data contract ─ ─ ─
                                │  opt-in forwarding
   TIER 3 ┌──────────────────────▼───────────────────────────┐
   opt-in │  masques.ai                                       │
   remote │  ClickHouse — personal namespace (v1.1)           │
          │              community pool (later, opt-in)        │
          │  the heavy OTEL collector / Docker lives HERE,     │
          │  not on the user's laptop                          │
          └────────────────────────────────────────────────────┘
```

**The inversion:** today the collector is summoned per session (`/audience start`)
and insight is on-demand. In v1.1 the *same* collector runs **always-on** — seated
once, left running — so capture is ambient and the baseline corpus accrues without
anyone thinking about it. The zero-infra, no-Docker version of this is the next
turn of the cybernetic loop (OQ1, deferred), not a v1.1 requirement.

---

## Phased Plan

### Phase 1 — The house is always open (persistent local audience)

Make capture ambient and Docker-free. This is the precondition for everything
else.

**Deliverables**
- Turn the existing collector compose into an **always-on appliance**. The
  groundwork is already there — `services/collector/docker-compose.yml` ships
  `restart: unless-stopped`, so crash/reboot recovery works once `up -d` has run.
  Remaining work: add a `healthcheck:` (probe the existing `:13133` endpoint) so
  the restart policy can catch a *hung* collector, not just a dead process; confirm
  Docker is set to start on login; document the seat-once workflow. The compose
  file is the management surface — start once, Docker keeps it alive. (No-Docker
  zero-infra capture is explicitly deferred — OQ1.)
- `/audience` rewritten from per-session summon to audience-lifecycle: `seat`
  (start the persistent collector + verify Claude Code telemetry env is set),
  `dismiss`, `status` (is the house open? how many sessions captured?), keep
  `logs`.
- Capture writes every session — masque and baseline — to local JSONL with a
  stable session boundary.
- `docs/otel-setup.md` rewritten around **seat-once always-on** setup rather than
  per-session `start`.

### Phase 2 — Honest scoring (lens-attributable lift + task-class)

Replace the activity proxies. Score every captured session.

**Deliverables**
- Heuristic task-class classifier (D5) over local session data.
- One-masque-per-session attribution flagging (D2).
- Optional `rubric` field added to `masque.schema.yaml` (D7); a rubric judge
  (Witness's natural job) that reads a session against the rubric and assigns the
  Layer-A band; cold-start fallback to the generic activity band for rubric-less
  masques. Wire draft-rubric proposal into the masque-creation flow.
- `services/judge/score.sql` demoted from verdict to supporting signal (D7);
  Layer-A 7-point reaction (D4) computed from rubric judge or activity fallback;
  Layer-B lift anchored to baseline deltas; update `sessions.sql`.
- `/performance` rewritten to surface the Layer-A reaction always, and Layer-B
  lift only once the baseline corpus is sufficient (never a misleading number).
- `docs/evaluation.md` rewritten to describe the two-layer, rubric-based scoring.

### Phase 3 — Personal reputation (accumulation)

Make the verdict accumulate. This is where "Codesmith beats baseline on Zig
refactors" first appears.

**Deliverables**
- Persistent personal reputation corpus (DuckDB or per-user masques.ai
  namespace).
- Cross-session aggregation: per (masque, task-class) lift with confidence/sample
  count.
- A `/reputation` view (or `/performance --history`) surfacing trends and
  thin-data honesty.

### Phase 4 — masques.ai + opt-in global (later)

The server tier and community pool. Designed for now, built after Phases 1–3
prove the loop.

**Deliverables**
- masques.ai ClickHouse personal namespace; opt-in forwarding of the Tier-2
  signal only.
- Anonymized community pool, normalization across users, anti-gaming.
- Explicit opt-in UX and a published, auditable data contract.

---

## Acceptance Criteria

### Tier 1 — Always-on capture (Phase 1)

- [ ] **C1:** The OTEL collector runs as an always-on persistent service
  (`restart: unless-stopped`) and survives a reboot; capture requires **no**
  per-session `/audience start`.
- [ ] **C2:** A `claude` session that **never** dons a masque is captured to local
  JSONL with a detectable session boundary.
- [ ] **C3:** A masque session and a baseline session are both present in the
  local record and distinguishable by a `masque` field (null for baseline).
- [ ] **C4:** `/audience status` reports the house open/closed and a count of
  captured sessions.

### Tier 2 — Honest scoring (Phase 2)

- [ ] **C5:** Each captured session is assigned a `task_class` by heuristic, with
  `unclassified` as a valid fallback. Baseline sessions classify too.
- [ ] **C6:** A session that switches masques mid-stream is flagged
  `attribution: mixed` and excluded from lift computation.
- [ ] **C7:** `/performance` emits a Layer-A house reaction on the 7-point scale
  (perfect…detracting) for **every** scored session, available from session one,
  with no baseline required.
- [ ] **C8:** Once a task-class has sufficient baseline sessions, `/performance`
  additionally reports Layer-B lift as a **delta vs the baseline corpus**, never a
  bare absolute level. Below threshold it shows only Layer A — never a misleading
  number.
- [ ] **C8b:** A masque carrying a `rubric` produces its Layer-A band from a
  qualitative read against that rubric; a masque without one falls back to an
  activity-only band. Verified with one rubric-bearing and one rubric-less masque.

### Tier 3 — Personal reputation (Phase 3)

- [ ] **C9:** Scores persist across sessions in a personal reputation corpus.
- [ ] **C10:** A per-(masque, task-class) lift figure with sample count is
  retrievable across multiple sessions.

### Tier 4 — Privacy contract (cross-cutting)

- [ ] **P1:** Nothing leaves the machine unless forwarding is explicitly opted in.
- [ ] **P2:** The forwarded payload contains only the Tier-2 derived signal (D3) —
  verified to contain no prompts, tool I/O, or code.

### Tier 5 — Documentation reframe

- [ ] **P3:** `docs/vision.md`, `docs/evaluation.md`, and `README` lead with
  **measurable identity / the persistent audience** as the product thesis.
- [ ] **P4:** `docs/future/` retains the payment/factory/marketplace vision,
  clearly marked deferred and distinct from this attainable layer.

---

## Open Questions

1. **OQ1 — Always-on mechanism. RESOLVED for v1.1:** keep the existing Docker OTEL
   collector, run it **always-on** (`restart: unless-stopped`, seated once). This
   preserves the keystone (D1) without new engineering. *Deferred standalone
   improvement:* a no-Docker, zero-infra capture path (native `otelcol` binary as a
   launchd/login service, a purpose-built local OTLP receiver, or a direct OTEL
   file sink) — revisit later as friction reduction on the cybernetic loop. Worth
   confirming when picked up: whether Claude Code's OTEL can write a clean local
   sink without any collector at all.
2. **OQ2 — Task-class heuristic boundaries.** Which observable signals best
   separate refactor/debug/greenfield/review/research/ops? Start coarse, refine.
3. **OQ3 — Baseline sufficiency threshold.** How many baseline sessions per
   task-class before lift is trustworthy enough to report?
4. **OQ4 — Schema touch.** Does task-class warrant an optional hint field on the
   masque schema, or stay purely inferred?
5. **OQ5 — Personal store location.** Persistent local DuckDB vs per-user
   masques.ai namespace for Phase 3 — and the migration path between them.
6. **OQ6 — Judge composition.** Resolved: the judge is a role; DuckDB is the
   mechanical default, an optional Witness-masque agent is a persistent qualitative
   judge (D7) — *a* judge, not *the* judge. Still open: when both a mechanical
   activity band and a qualitative judge band exist for one session, which wins, or
   how do they merge? And does a Witness judge run *inside* the always-on audience,
   or get summoned per scoring?
7. **OQ7 — Rubric format & trust.** Prose criteria (matching the prose-first
   philosophy of `lens`/`context`) vs. structured weighted dimensions? Required or
   optional on the schema? And the gaming concern: personal reputation tolerates a
   self-authored rubric, but the global pool (Phase 4) likely needs normalized or
   reviewed rubrics — decide the standardization model before global ships.

---

## What's Preserved / Retired

**Preserved:** masque schema, all personas, the don/doff/id/list loop, the TUI,
DuckDB as the local scorer, ClickHouse as the reputation store (relocated to
masques.ai), the theatrical metaphor.

**Retired:** `/audience` as a per-session Docker summon (becomes a seat-once
always-on lifecycle); the five proxies *as a masque verdict* (repurposed as honest
Layer-A inputs, no longer sold as masque-attribution); on-demand-only scoring.

**Deferred standalone improvement:** a no-Docker, zero-infra always-on capture
path (OQ1) — a later turn of the cybernetic loop, not v1.1.

**Deferred (unchanged, in `docs/future/`):** payments, the agent-factory rewrite,
the marketplace economy, global reputation-for-sale.
