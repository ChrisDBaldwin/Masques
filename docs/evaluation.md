# Evaluation — Measurable Identity

The point of a masque is not that you wore it; it's whether wearing it made the
work better. **Measurable identity** is the product: an always-on audience
watches every session and tells you, honestly, how a masque performed *for you,
on your work*.

This is a deliberately modest, personal claim — not a universal benchmark. Your
audience compares *your* masque sessions to *your* baseline. The honesty comes
from the audience never leaving (it is [always seated](otel-setup.md)), so a
baseline accrues on its own and lift can be measured against it.

```
Every claude session (masque OR baseline)
  └── OTEL (always on) ──→ local JSONL ──→ the judge (DuckDB) ──→ two-layer score
                                                 │
                              Layer A: 7-point house reaction (always)
                              Layer B: lift vs YOUR baseline (once earned)
```

## The two layers (PRD D4)

Lift is the honest comparative verdict — but it can't exist on session one,
before any baseline exists. Forcing you to wait for "enough data" is the
cold-start trap. So scoring has two layers.

### Layer A — the house reaction (from session one)

A single qualitative verdict on a **7-point scale**, oriented positive or
negative immediately, like a soapstone rating:

> **perfect · great · good · neutral · bad · awful · detracting**

It is an *absolute* read of how the session went, from observable signals
(tool success, throughput, cost, friction). It answers *"how did this go?"* — it
never claims the masque *caused* it. The audience always has something to say.

**Where the band comes from:**

- **Rubric judge (meaningful).** If the masque carries a [`rubric`](schema.md)
  (D7) and a judge has read the session against it — an LLM pass, optionally a
  persistently-running **Witness** masque — that judge supplies the band
  (`judge: rubric`). The rubric is the measurable shadow of the lens: a great
  Codesmith session is one where *every line teaches*, which no generic metric
  can see.
- **Activity fallback (cold-start).** No rubric, or no judge configured? The
  band falls back to a generic activity composite (`judge: activity-fallback`).
  Every masque still gets a reaction from session one.

The activity composite is `0.35·success + 0.20·throughput + 0.20·cost +
0.25·low-friction` on a 0–10 scale, mapped to the 7 bands. These weights and
cutoffs are first-pass and centralized for tuning (PRD OQ2/OQ3).

### Layer B — lift (once the corpus thickens)

Once enough same-task-class sessions exist, the audience adds the comparative
verdict: **relative lift vs your baseline corpus** — e.g. *"Codesmith completes
refactor work with 22% fewer failed tool calls than your baseline."* This is the
masque-attribution layer, and it is always a **difference**, never an absolute
level.

Layer B is shown **only** when it has earned the right to:

- the session's attribution is `clean` (one masque), and
- the baseline cohort for that task-class has ≥ `BASELINE_MIN` sessions
  (default 5), and
- the masque has ≥ 1 clean session of that class.

Otherwise the audience states why, plainly — `not_yet` (baseline too thin),
`n/a` (this *is* a baseline session), or `excluded` (mixed attribution) — and
shows **no number**. Never a misleading figure.

## Clean attribution without a factory (PRD D2)

Lift is only honest when "baseline" really is masque-free. v1.1 scores at the
**session grain**: each `claude` invocation is already its own process.

- never donned → a clean **baseline** sample
- donned once, early → a clean **masque** sample
- switched masques mid-session → **mixed**, excluded from lift (still scored for
  your own curiosity)

This is how masques are used in practice (spawn an agent, don immediately, hand
it a task), so "one masque per scored session" is a measurement-hygiene
discipline, not a new constraint. Attribution is recorded by `/don` into a local
[sidecar map](otel-setup.md#how-masque-vs-baseline-is-distinguished); no
agent-factory rewrite needed.

## Task-class (PRD D5)

Lift only compares *the same kind of work*. Task-class is the bucket, **inferred
from signals the always-on audience already sees** — tool mix, edit/read ratio,
session shape — so it works for **all** sessions, including baselines that never
declared an intent. Starter buckets: `refactor · debug · greenfield · review ·
research · ops · unclassified`. The classifier is coarse and transparent by
design, and explicitly refinable (OQ2).

## The judge is a role, not one component (PRD D7)

- **DuckDB** is the mechanical, always-on default: it classifies, attributes,
  produces the activity-fallback band, and computes lift. It cannot read prose,
  so it never produces the *rubric* band.
- A **Witness-masque agent** is an optional qualitative judge — an attentive
  critic in the audience that reads the session against the rubric and upgrades
  Layer A from meter to critic. Witness is *a* judge, not *the* judge.

The old five proxies (tool-success, tools/prompt, tools/min, cache ratio,
cost/tool) used to *be* the masque verdict. They were masque-agnostic — identical
with or without a masque — so they are **demoted** to `supporting_signals`:
context that describes a session, never a claim about the masque.

## Output

`services/judge/judge.sh` (or `/performance`) emits:

```yaml
session: 7c8f7b8b-...
masque: Codesmith            # null (baseline) for un-donned sessions
attribution: clean           # clean | mixed | baseline
task_class: refactor
duration_min: 69.0
layer_a:
  reaction: great            # perfect>great>good>neutral>bad>awful>detracting
  judge: activity-fallback   # or: rubric
  activity_band: great
  activity_score: 8.69
layer_b:
  status: shown
  vs: your baseline corpus (same task_class)
  failed_tool_calls_lift_pct: +34.3
  baseline_sessions: 15
  masque_sessions: 3
supporting_signals:          # demoted proxies — context, not the verdict
  tool_success_pct: 98
  tools: 41
  ...
tool_mix: { read: 7, edit: 8, write: 5, bash: 21, search: 0, web: 0 }
```

## Running

```bash
./services/judge/judge.sh                                  # most recent session
TARGET_SESSION="$CLAUDE_CODE_SESSION_ID" ./services/judge/judge.sh   # this session
BASELINE_MIN=8 ./services/judge/judge.sh                   # require a thicker baseline
RUBRIC_BAND=great ./services/judge/judge.sh                # supply a rubric-judge band
# or:
/performance
```

Requires DuckDB and telemetry in `services/collector/data/logs.jsonl`.

## Persistent reputation (Phase 3 — designed, not yet built)

Layers A and B score *sessions*. Making the verdict **accumulate** —
per-(masque, task-class) lift with a sample count, across many sessions and
machines, so "Codesmith beats my baseline on refactors" becomes a standing fact
— is Phase 3 (a persistent personal corpus). The opt-in global community pool,
with normalization and anti-gaming, is Phase 4. Both are designed but not yet
built; the payment/marketplace economy remains deferred in
[`docs/future/`](future/).
