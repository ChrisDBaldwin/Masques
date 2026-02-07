---
name: performance
description: Show quantitative performance metrics for the current masque session
arguments: []
---

# Performance Command

Display telemetry-based performance scoring for the current masque session. Complements `/id` (identity) and the Witness masque (qualitative fit) with quantitative data from OTEL telemetry.

## Instructions

### Step 1: Check Prerequisites

1. Verify the judge script exists:
```bash
test -f ${CLAUDE_PLUGIN_ROOT}/services/judge/judge.sh && echo "ok" || echo "missing"
```

2. Check for DuckDB:
```bash
command -v duckdb && echo "ok" || echo "missing"
```

If DuckDB is missing, report:
```
Performance scoring requires DuckDB.
Install: brew install duckdb
```

3. Check for telemetry data:
```bash
test -f ${CLAUDE_PLUGIN_ROOT}/services/collector/data/logs.jsonl && echo "ok" || echo "no data"
```

If no data, report:
```
No telemetry data found.

To start collecting:
  1. /audience start        — launch the collector
  2. /audience config       — configure Claude Code telemetry
  3. Start a new session    — data flows automatically

Requires OTEL_LOG_TOOL_DETAILS=1 for masque session detection.
```

### Step 2: Read Current Masque

Read `.claude/masque.session.yaml` to get the active masque name and donned_at time.

### Step 3: Run the Judge

Execute the scoring script:
```bash
${CLAUDE_PLUGIN_ROOT}/services/judge/judge.sh
```

The script outputs YAML with:
- `masque` — name of the scored masque
- `duration_min` — session length in minutes
- `dimensions` — quality, autonomy, productivity, token_efficiency, cost_efficiency (0-10 each)
- `composite` — weighted composite score (0-10)
- `recommendation` — `keep`, `review`, or `doff`
- `stats` — raw counts (cost, tools, prompts, tokens)

### Step 4: Display Results

Parse the YAML output and display as a visual dashboard:

```
Performance: [masque] ([duration] min)
═══════════════════════════════════════
  Quality:          [score]  [bar]
  Autonomy:         [score]  [bar]
  Productivity:     [score]  [bar]
  Token Efficiency: [score]  [bar]
  Cost Efficiency:  [score]  [bar]

  Composite: [score] / 10 → [recommendation]
  Cost: $[cost] | Tools: [total] ([pct]% ok) | Prompts: [count]
```

**Bar rendering**: Each score maps to a 10-character bar where each full block = 1 point.
Use `█` for full points, `▌` for half points, `░` for empty.

Example: score 7.5 → `███████▌░░`

**Recommendation styling**:
- `keep` — "masque is amplifying"
- `review` — "check masque fit"
- `doff` — "masque may be constraining"

### Step 5: Handle Errors

If the judge script fails:
- Parse stderr for the error message
- Common issues:
  - "duckdb not found" → suggest `brew install duckdb`
  - "no logs data" → suggest `/audience start` and running a session
  - SQL errors → likely the JSONL structure doesn't match expected schema; suggest checking `/audience logs` for the actual event format

### Step 6: Suggest Next Actions

- "Use `/id` to see current masque identity"
- "Use `/audience logs` to inspect raw telemetry"
- "Use `/inspect` to review masque lens and context"

**Important caveat**: The DuckDB SQL is best-effort based on the OTLP JSON spec. If scores look wrong, the JSONL structure may differ from expected — check `services/collector/data/logs.jsonl` to see the actual format and adjust `services/judge/sessions.sql` and `score.sql` accordingly.

## Dimensions Explained

| Dimension | Weight | Source | Measures |
|-----------|--------|--------|----------|
| Quality | 30% | tool_result success/failure | Did tools work? Low rejection rate? |
| Autonomy | 25% | user_prompt count vs tool_result count | More agent actions per prompt = better |
| Productivity | 20% | tool completions / time | Throughput per minute |
| Token Efficiency | 15% | cache_read_tokens / total_tokens | Cache utilization |
| Cost Efficiency | 10% | cost_usd / tool completions | Cost per unit of work |

**Composite scoring**: weighted sum → 0-10 scale.
- **>= 7**: `keep` — masque is amplifying
- **4-6.9**: `review` — check fit
- **< 4**: `doff` — masque is constraining

## Tool Calls Summary

This command requires:
- 1-3 tool calls for prerequisite checks
- 1 tool call to read session state
- 1 tool call to run the judge script
