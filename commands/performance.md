---
name: performance
description: Show the audience's two-layer reaction (and lift, once earned) for a session
arguments: []
---

# Performance Command

Show how the always-on audience scored a session. Output has **two layers**
(PRD D4):

- **Layer A — the house reaction** (always, from session one): a single
  7-point verdict — `perfect · great · good · neutral · bad · awful ·
  detracting`. An honest read of *how the session went*, never a claim that the
  masque caused it.
- **Layer B — lift** (only once earned): how the masque compares to *your own
  baseline corpus* on the same task-class — a **delta**, never a bare level.
  Hidden until the baseline is thick enough. The audience never shows a
  misleading number.

This replaces the old five-proxy "masque verdict." Those proxies were
masque-agnostic — they scored the same with or without a masque — so they are
**demoted** to `supporting_signals` (context), never the verdict (PRD D7).

## Instructions

### Step 1: Check Prerequisites

1. Judge script present:
```bash
test -f ${CLAUDE_PLUGIN_ROOT}/services/judge/judge.sh && echo ok || echo missing
```
2. DuckDB present:
```bash
command -v duckdb >/dev/null && echo ok || echo missing
```
If missing: "Scoring requires DuckDB. Install: brew install duckdb."
3. Telemetry data present:
```bash
test -f ${CLAUDE_PLUGIN_ROOT}/services/collector/data/logs.jsonl && echo ok || echo "no data"
```
If no data: the audience hasn't captured anything yet — "Run `/audience seat`
to open the house (it stays open), then start a session." Note capture needs
the Claude Code OTEL env (see `/audience seat`).

### Step 2: Identify the session to score

By default the judge scores the **most recent** session. To score *this*
session explicitly, pass its id (which is also what `/don` records for
attribution):
```bash
echo "$CLAUDE_CODE_SESSION_ID"
```
Optionally read `.claude/masque.session.yaml` to mention the active masque by
name in your framing.

### Step 3: Run the judge

```bash
TARGET_SESSION="$CLAUDE_CODE_SESSION_ID" ${CLAUDE_PLUGIN_ROOT}/services/judge/judge.sh
```
(Omit `TARGET_SESSION` to score the most recent session.) Optional knobs:
- `BASELINE_MIN=N` — baseline sessions per task-class before Layer-B lift shows
  (default 5).
- `RUBRIC_BAND=<band>` — if a rubric judge (an LLM pass, or a Witness-masque
  agent — D7) has read the session against the masque's `rubric` and produced a
  band, pass it here; the judge will use it for Layer A (`judge: rubric`)
  instead of the activity fallback.

The judge emits YAML:
```yaml
session: <id>
masque: <name | null (baseline)>
attribution: <clean | mixed | baseline>
task_class: <refactor|debug|greenfield|review|research|ops|unclassified>
duration_min: <n>
layer_a:
  reaction: <perfect..detracting>
  judge: <activity-fallback | rubric>
  activity_band: <band>        # the activity-only band, shown for transparency
  activity_score: <0-10>
layer_b:
  status: <shown | not_yet | n/a ... | excluded ...>
  # when shown:
  failed_tool_calls_lift_pct: <+/-n>
  baseline_sessions: <n>
  masque_sessions: <n>
supporting_signals: { ... }    # demoted proxies — context, not the verdict
tool_mix: { ... }
```

### Step 4: Display

Lead with Layer A. Show Layer B **only** when `layer_b.status: shown` — otherwise
print the one-line honest reason, never invent a number.

```
Audience reaction: GREAT   (codesmith · refactor · 38 min)
  judge: rubric            ← or "activity-fallback" when no rubric judge ran

Lift vs your baseline (refactor):
  failed tool calls: -22%   (you make 22% fewer)   [5 baseline · 3 masque sessions]
```

When Layer B is not earned, render its status plainly, e.g.:
```
Lift: not yet — baseline corpus too thin for refactor (3 / 5 sessions needed)
```
```
Lift: n/a — this is a baseline session (nothing to lift against)
```
```
Lift: excluded — mixed attribution (more than one masque this session)
```

Render the 7-point reaction with orientation (color/emphasis your call):
`perfect · great · good` positive, `neutral` flat, `bad · awful · detracting`
negative.

Then a compact supporting-signals line, clearly subordinate:
```
  supporting: 95% tool success · 41 tools · $0.00 · 4.5 tools/min
  tool mix: read 7 · edit 8 · write 5 · bash 21 · search 0 · web 0
```

### Step 5: Errors

Parse stderr from the judge:
- "duckdb not found" → `brew install duckdb`.
- "no logs" → `/audience seat` and run a session.
- A SQL/parse error → the JSONL shape may have drifted; inspect
  `services/collector/data/logs.jsonl` and `services/judge/sessions.sql`.

### Step 6: Next actions

- "`/id` — current masque identity."
- "`/audience status` — is the house open, how many sessions captured."
- "`/inspect` — the masque's lens, context, and rubric."

## How the two layers are computed

| Layer | Question | Source | Shows when |
|-------|----------|--------|------------|
| A — reaction | How did this session go? | Rubric judge (D7) if available, else activity composite (success, throughput, cost, low-friction) mapped to 7 bands | Always, from session one |
| B — lift | Did the masque beat *your* baseline? | Δ vs your baseline corpus, same task-class (failed-tool-call rate) | Only when baseline ≥ threshold AND attribution is clean |

**Honesty rules:**
- Layer B is a **difference**, never an absolute level.
- Below the baseline threshold, or for `baseline`/`mixed` sessions, Layer B is
  suppressed with a stated reason — never a fabricated number.
- `supporting_signals` are activity proxies; they describe the session, they do
  **not** attribute outcome to the masque.

## Tool Calls Summary

- 1–3 prerequisite checks
- 1 to read the session id / active masque
- 1 to run the judge
