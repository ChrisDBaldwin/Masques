-- score.sql — Compute 5 performance dimensions + composite score
--
-- Reads raw_logs and masque_sessions (from sessions.sql) and scores
-- events within the most recent session across 5 dimensions:
--
--   Quality (30%)        — tool success rate
--   Autonomy (25%)       — tool actions per user prompt
--   Productivity (20%)   — tool completions per minute
--   Token Efficiency (15%) — cache hit ratio
--   Cost Efficiency (10%)  — cost per tool completion
--
-- Output: YAML to stdout

-- Score the most recent masque session
WITH session AS (
  SELECT * FROM masque_sessions ORDER BY don_time DESC LIMIT 1
),

-- Count tool results within the session window
tool_events AS (
  SELECT
    attr(attributes, 'success') AS success,
    attr(attributes, 'tool_name') AS tool_name
  FROM raw_logs, session s
  WHERE event_type = 'claude_code.tool_result'
    AND event_time BETWEEN s.don_time AND s.doff_time
),

-- Count user prompts within the session window
prompt_events AS (
  SELECT COUNT(*) AS prompt_count
  FROM raw_logs, session s
  WHERE event_type = 'claude_code.user_prompt'
    AND event_time BETWEEN s.don_time AND s.doff_time
),

-- Extract API request costs and token usage
api_events AS (
  SELECT
    COALESCE(attr(attributes, 'cost_usd'), '0')::DOUBLE AS cost_usd,
    COALESCE(attr(attributes, 'cache_read_tokens'), '0')::BIGINT AS cache_read_tokens,
    COALESCE(attr(attributes, 'input_tokens'), '0')::BIGINT AS input_tokens,
    COALESCE(attr(attributes, 'output_tokens'), '0')::BIGINT AS output_tokens
  FROM raw_logs, session s
  WHERE event_type = 'claude_code.api_request'
    AND event_time BETWEEN s.don_time AND s.doff_time
),

-- Aggregate metrics
metrics AS (
  SELECT
    COUNT(*) AS total_tools,
    COUNT(*) FILTER (WHERE success = 'true') AS tools_ok,
    (SELECT GREATEST(prompt_count, 1) FROM prompt_events) AS prompts,
    (SELECT GREATEST(duration_min, 1) FROM session) AS duration_min,
    (SELECT masque_name FROM session) AS masque_name
  FROM tool_events
),

api_agg AS (
  SELECT
    COALESCE(SUM(cost_usd), 0) AS total_cost,
    COALESCE(SUM(cache_read_tokens), 0) AS total_cache_tokens,
    COALESCE(SUM(input_tokens + output_tokens), 1) AS total_tokens
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

    -- Quality: tool success rate -> 0-10
    LEAST(10, ROUND((m.tools_ok::DOUBLE / GREATEST(m.total_tools, 1)) * 10, 1)) AS quality,

    -- Autonomy: tool actions per prompt -> 0-10 (5+ tools/prompt = 10)
    LEAST(10, ROUND((m.total_tools::DOUBLE / m.prompts) * 2, 1)) AS autonomy,

    -- Productivity: tool completions per minute -> 0-10 (1+/min = 10)
    LEAST(10, ROUND((m.tools_ok::DOUBLE / m.duration_min) * 10, 1)) AS productivity,

    -- Token Efficiency: cache ratio -> 0-10
    LEAST(10, ROUND((a.total_cache_tokens::DOUBLE / GREATEST(a.total_tokens, 1)) * 10, 1)) AS token_efficiency,

    -- Cost Efficiency: inverse cost per tool -> 0-10
    -- $0 = 10, $0.01/tool = 8, $0.05/tool = 5, $0.10+/tool = 2
    LEAST(10, GREATEST(0, ROUND(
      10 - (a.total_cost / GREATEST(m.tools_ok, 1)) * 100,
    1))) AS cost_efficiency
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
    1) AS composite,
    CASE
      WHEN (quality * 0.30 + autonomy * 0.25 + productivity * 0.20 +
            token_efficiency * 0.15 + cost_efficiency * 0.10) >= 7 THEN 'keep'
      WHEN (quality * 0.30 + autonomy * 0.25 + productivity * 0.20 +
            token_efficiency * 0.15 + cost_efficiency * 0.10) >= 4 THEN 'review'
      ELSE 'doff'
    END AS recommendation
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
) AS yaml_output
FROM final;
