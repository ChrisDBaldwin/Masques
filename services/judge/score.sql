-- score.sql — Compute 5 performance dimensions + composite score
--
-- Reads raw_logs (from sessions.sql) and scores events within
-- masque session windows across 5 dimensions:
--
--   Quality (30%)        — tool success rate, low rejection
--   Autonomy (25%)       — agent actions per user prompt
--   Productivity (20%)   — tool completions per minute
--   Token Efficiency (15%) — cache hit ratio
--   Cost Efficiency (10%)  — cost per tool completion
--
-- Output: YAML to stdout via printf-style SELECT

-- Score the most recent masque session
WITH session AS (
  SELECT * FROM masque_sessions ORDER BY don_time DESC LIMIT 1
),

-- Count tool results within the session window
tool_events AS (
  SELECT
    COALESCE(
      json_extract_string(body::JSON, '$.success'),
      json_extract_string(attributes, '$[?(@.key=="success")].value.stringValue'),
      'true'
    ) as success,
    COALESCE(
      json_extract_string(body::JSON, '$.tool_name'),
      json_extract_string(attributes, '$[?(@.key=="tool_name")].value.stringValue'),
      'unknown'
    ) as tool_name
  FROM raw_logs, session s
  WHERE epoch_ms(timeUnixNano::BIGINT / 1000000) BETWEEN s.don_time AND s.doff_time
    AND (
      json_extract_string(body::JSON, '$.event_type') = 'tool_result'
      OR json_extract_string(attributes, '$[?(@.key=="event_type")].value.stringValue') = 'tool_result'
    )
),

-- Count user prompts within the session window
prompt_events AS (
  SELECT COUNT(*) as prompt_count
  FROM raw_logs, session s
  WHERE epoch_ms(timeUnixNano::BIGINT / 1000000) BETWEEN s.don_time AND s.doff_time
    AND (
      json_extract_string(body::JSON, '$.event_type') = 'user_prompt'
      OR json_extract_string(attributes, '$[?(@.key=="event_type")].value.stringValue') = 'user_prompt'
    )
),

-- Extract API request costs and token usage
api_events AS (
  SELECT
    COALESCE(
      json_extract_string(body::JSON, '$.cost_usd'),
      json_extract_string(attributes, '$[?(@.key=="cost_usd")].value.doubleValue'),
      '0'
    )::DOUBLE as cost_usd,
    COALESCE(
      json_extract_string(body::JSON, '$.cache_read_tokens'),
      json_extract_string(attributes, '$[?(@.key=="cache_read_tokens")].value.intValue'),
      '0'
    )::BIGINT as cache_read_tokens,
    COALESCE(
      json_extract_string(body::JSON, '$.total_tokens'),
      json_extract_string(attributes, '$[?(@.key=="total_tokens")].value.intValue'),
      '0'
    )::BIGINT as total_tokens
  FROM raw_logs, session s
  WHERE epoch_ms(timeUnixNano::BIGINT / 1000000) BETWEEN s.don_time AND s.doff_time
    AND (
      json_extract_string(body::JSON, '$.event_type') = 'api_request'
      OR json_extract_string(attributes, '$[?(@.key=="event_type")].value.stringValue') = 'api_request'
    )
),

-- Aggregate metrics
metrics AS (
  SELECT
    -- Tool metrics
    COUNT(*) as total_tools,
    COUNT(*) FILTER (WHERE success = 'true') as tools_ok,
    -- From prompt_events
    (SELECT GREATEST(prompt_count, 1) FROM prompt_events) as prompts,
    -- Session duration
    (SELECT GREATEST(duration_min, 1) FROM session) as duration_min,
    -- Masque info
    (SELECT masque_name FROM session) as masque_name
  FROM tool_events
),

api_agg AS (
  SELECT
    COALESCE(SUM(cost_usd), 0) as total_cost,
    COALESCE(SUM(cache_read_tokens), 0) as total_cache_tokens,
    COALESCE(SUM(total_tokens), 1) as total_tokens
  FROM api_events
),

-- Compute dimension scores (0-10 scale)
scores AS (
  SELECT
    m.masque_name,
    m.duration_min,
    m.total_tools,
    m.tools_ok,
    m.prompts,
    a.total_cost,
    a.total_cache_tokens,
    a.total_tokens,

    -- Quality: tool success rate → 0-10
    LEAST(10, ROUND((m.tools_ok::DOUBLE / GREATEST(m.total_tools, 1)) * 10, 1)) as quality,

    -- Autonomy: tool actions per prompt → 0-10 (5+ tools/prompt = 10)
    LEAST(10, ROUND((m.total_tools::DOUBLE / m.prompts) * 2, 1)) as autonomy,

    -- Productivity: tool completions per minute → 0-10 (1+/min = 10)
    LEAST(10, ROUND((m.tools_ok::DOUBLE / m.duration_min) * 10, 1)) as productivity,

    -- Token Efficiency: cache ratio → 0-10
    LEAST(10, ROUND((a.total_cache_tokens::DOUBLE / GREATEST(a.total_tokens, 1)) * 10, 1)) as token_efficiency,

    -- Cost Efficiency: inverse cost per tool → 0-10
    -- $0 = 10, $0.01/tool = 8, $0.05/tool = 5, $0.10+/tool = 2
    LEAST(10, GREATEST(0, ROUND(
      10 - (a.total_cost / GREATEST(m.tools_ok, 1)) * 100,
    1))) as cost_efficiency
  FROM metrics m, api_agg a
),

-- Compute composite and recommendation
final AS (
  SELECT
    *,
    ROUND(
      quality * 0.30 +
      autonomy * 0.25 +
      productivity * 0.20 +
      token_efficiency * 0.15 +
      cost_efficiency * 0.10,
    1) as composite,
    CASE
      WHEN (quality * 0.30 + autonomy * 0.25 + productivity * 0.20 +
            token_efficiency * 0.15 + cost_efficiency * 0.10) >= 7 THEN 'keep'
      WHEN (quality * 0.30 + autonomy * 0.25 + productivity * 0.20 +
            token_efficiency * 0.15 + cost_efficiency * 0.10) >= 4 THEN 'review'
      ELSE 'doff'
    END as recommendation
  FROM scores
)

-- Output as YAML
SELECT printf('masque: %s
duration_min: %.0f
dimensions:
  quality: %.1f
  autonomy: %.1f
  productivity: %.1f
  token_efficiency: %.1f
  cost_efficiency: %.1f
composite: %.1f
recommendation: %s
stats:
  total_cost: %.2f
  total_tools: %d
  tools_ok: %d
  tool_success_pct: %.0f
  prompts: %d
  total_tokens: %d
  cache_tokens: %d',
  masque_name, duration_min,
  quality, autonomy, productivity, token_efficiency, cost_efficiency,
  composite, recommendation,
  total_cost, total_tools, tools_ok,
  (tools_ok::DOUBLE / GREATEST(total_tools, 1)) * 100,
  prompts, total_tokens, total_cache_tokens
) as yaml_output
FROM final;
