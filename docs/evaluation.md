# Evaluation

**DuckDB Performance** scores a single masque session — "how well did the agent work just now?" Local, ephemeral, immediate feedback. This is the scoring system in the current minimal product.

```
OTEL Collector
  └── JSONL (local) ──→ DuckDB ──→ Session score (YAML)
                                    quality/autonomy/productivity/...
                                    → keep / review / doff
```

Persistent, identity-level **reputation** scoring (aggregating signals across many sessions, with an economic/payment dimension) is deferred future work. See [`docs/future/`](future/).

## DuckDB Performance Scoring

Runs locally via `services/judge/judge.sh`. Reads OTEL JSONL exports, scores the most recent masque session, outputs YAML to stdout. No persistent state — ephemeral by design.

### Data Source

The OTEL collector writes `logs.jsonl` in OTLP format. The judge flattens the three-level hierarchy (`resourceLogs → scopeLogs → logRecords`) and extracts events within the session window (don to doff).

Three event types matter:
- `claude_code.tool_result` — tool invocations with `success` and `tool_name` attributes
- `claude_code.user_prompt` — user messages (measures how much the agent does per prompt)
- `claude_code.api_request` — API calls with `cost_usd`, token counts, and cache stats

### Dimensions

All dimensions score on a 0–10 scale.

| Dimension | Weight | What it measures | Scaling |
|-----------|--------|-----------------|---------|
| **Quality** | 30% | Tool success rate | `(tools_ok / total_tools) × 10` |
| **Autonomy** | 25% | Tool actions per user prompt | `(total_tools / prompts) × 2` — caps at 5+ tools/prompt |
| **Productivity** | 20% | Tool completions per minute | `(tools_ok / duration_min) × 10` — caps at 1+/min |
| **Token Efficiency** | 15% | Cache hit ratio | `(cache_tokens / total_tokens) × 10` |
| **Cost Efficiency** | 10% | Inverse cost per tool completion | `10 − (cost / tools_ok) × 100` — $0 = 10, $0.01/tool ≈ 8, $0.05/tool ≈ 5 |

### Composite Score

Weighted sum of all dimensions:

```
composite = quality×0.30 + autonomy×0.25 + productivity×0.20
          + token_efficiency×0.15 + cost_efficiency×0.10
```

### Recommendation

| Composite | Recommendation | Meaning |
|-----------|---------------|---------|
| ≥ 7.0 | **keep** | Masque is performing well |
| 4.0 – 6.9 | **review** | Investigate before continuing |
| < 4.0 | **doff** | Switch masques or return to baseline |

### Output

```yaml
masque: Codesmith
duration_min: 45
dimensions:
  quality: 9.2
  autonomy: 7.4
  productivity: 6.0
  token_efficiency: 8.1
  cost_efficiency: 7.5
composite: 7.8
recommendation: keep
stats:
  total_cost: 0.34
  total_tools: 87
  tools_ok: 80
  tool_success_pct: 92
  prompts: 12
  total_tokens: 142000
  cache_tokens: 98000
```

### Running

```bash
# Direct
./services/judge/judge.sh

# Via plugin
/performance
```

Requires DuckDB installed and telemetry data in `services/collector/data/logs.jsonl`.

## Reputation (deferred)

Persistent, identity-level reputation scoring — aggregating signals across many sessions into a long-lived score per identity, including an economic/payment dimension — was part of the agent-marketplace vision and is **not** in the current minimal product. The ClickHouse schema that backed it has been removed.

The intended bridge was for DuckDB session scores to feed a reputation store as `task_quality` signals, accumulating into a trend-aware per-identity score. That design is preserved in [`docs/future/`](future/) for when masques grows into a marketplace.
