# Evaluation & Reputation

Masques has two scoring systems that measure different things at different timescales.

**DuckDB Performance** scores a single masque session — "how well did the agent work just now?" Local, ephemeral, immediate feedback.

**ClickHouse Reputation** scores an identity over time — "how reliable is this agent across all its work?" Remote, persistent, trend-aware.

```
OTEL Collector
  ├── JSONL (local) ──→ DuckDB ──→ Session score (YAML)
  │                                 quality/autonomy/productivity/...
  │                                 → keep / review / doff
  │
  └── ClickHouse (remote) ──→ reputation_events
                               → reputation_scores_mv
                               → overall score + category breakdown
```

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

## ClickHouse Reputation Scoring

Persistent, identity-level scoring stored in ClickHouse. Reputation aggregates signals across all sessions and interactions — not just one session.

### reputation_events

Raw signals that feed into scoring. Each event is a single data point about an identity's behavior.

| Column | Type | Description |
|--------|------|-------------|
| `event_id` | UUID | Unique event identifier |
| `timestamp` | DateTime64(3) | When the event occurred |
| `identity_id` | UUID | The identity being scored |
| `category` | String | One of: `task_quality`, `economic`, `identity_hygiene` |
| `event_type` | String | Specific signal — e.g. `task_completed`, `payment_failed`, `key_rotated` |
| `score_delta` | Float32 | Positive or negative impact on score |
| `confidence` | Float32 | Signal confidence (0–1, default 1.0) |
| `reference_type` | String | What this event refers to — `session`, `transaction`, or `attestation` |
| `reference_id` | String | ID of the referenced object |
| `attributes` | Map(String, String) | Additional context as key-value pairs |

Partitioned by month, TTL 3 years.

### reputation_scores

Aggregated scores per identity. Uses `ReplacingMergeTree(computed_at)` so only the latest score per identity survives deduplication.

| Column | Type | Description |
|--------|------|-------------|
| `identity_id` | UUID | The scored identity |
| `computed_at` | DateTime64(3) | When this score was computed |
| `overall_score` | Float32 | Weighted composite of category scores |
| `task_quality_score` | Float32 | Average score_delta for `task_quality` events |
| `economic_score` | Float32 | Average score_delta for `economic` events |
| `identity_hygiene_score` | Float32 | Average score_delta for `identity_hygiene` events |
| `total_events` | UInt64 | Events in the scoring window |
| `positive_events` | UInt64 | Events with positive score_delta |
| `negative_events` | UInt64 | Events with negative score_delta |
| `confidence` | Float32 | `min(1.0, total_events / 100)` — ramps up with data volume |
| `score_7d_ago` | Float32 | Score snapshot for 7-day trend |
| `score_30d_ago` | Float32 | Score snapshot for 30-day trend |

### Categories

| Category | Weight | What it tracks | Example events |
|----------|--------|---------------|----------------|
| **task_quality** | 40% | How well the identity performs work | `task_completed`, `task_failed`, `review_positive` |
| **economic** | 35% | Payment and financial behavior | `payment_completed`, `payment_failed`, `settlement_delayed` |
| **identity_hygiene** | 25% | Identity management practices | `key_rotated`, `session_expired`, `credential_leaked` |

### Materialized View

`reputation_scores_mv` auto-updates `reputation_scores` when new events arrive. It:

1. Looks at the last 90 days of `reputation_events`
2. Computes average `score_delta` per category per identity
3. Produces a weighted composite: `task_quality×0.40 + economic×0.35 + identity_hygiene×0.25`
4. Sets confidence based on event volume: `min(1.0, total_events / 100)`

### Schema

```
sql/006_reputation.sql
├── reputation_events         MergeTree, partitioned by month, 3-year TTL
├── reputation_scores         ReplacingMergeTree(computed_at), no TTL
└── reputation_scores_mv      Materialized view, auto-aggregates on insert
```

## How the Two Systems Relate

They measure different things and operate independently:

| | DuckDB Performance | ClickHouse Reputation |
|---|---|---|
| **Scope** | Single session | All sessions over time |
| **Subject** | A masque session | An identity |
| **Storage** | Ephemeral (in-memory) | Persistent (ClickHouse) |
| **Input** | Local OTEL JSONL | reputation_events table |
| **Trigger** | On-demand (`/performance`) | Continuous (materialized view) |
| **Time window** | One don-to-doff session | Rolling 90 days |
| **Output** | YAML with keep/review/doff | Score with confidence and trends |

The planned connection: DuckDB session scores will feed into ClickHouse as `reputation_events` with `category = 'task_quality'` and `reference_type = 'session'`. This bridges immediate session feedback into long-term reputation.
