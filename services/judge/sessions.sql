-- sessions.sql — Enumerate EVERY captured session and derive its signals.
--
-- v1.1 (Persistent Audience): the audience is always seated, so the record
-- holds every session — masque AND baseline. This script no longer scores a
-- single donned masque; it builds one row per session.id with:
--   - boundaries (don/doff/duration)               [C2: detectable boundary]
--   - tool-mix + shape aggregates                  (Layer-A + task-class inputs)
--   - heuristic task_class                         [C5, PRD D5 — refine: OQ2]
--   - masque attribution: clean | mixed | baseline [C3/C6, PRD D2]
--
-- Inputs (set by judge.sh before .read):
--   logs_path        — path to the collector's logs.jsonl
--   attribution      — a pre-created table (session_id, masque, donned_at);
--                      empty when no sidecar map exists (then every session is
--                      a baseline). judge.sh creates it from the optional
--                      sidecar file services/collector/data/sessions.attribution.jsonl.
--
-- Output: table `sessions`.

-- Helper: extract a string attribute from the OTLP attributes array.
-- Note: OTLP encodes attribute values as one of stringValue / intValue /
-- doubleValue (cost_usd is a double — missing it silently zeroed cost).
CREATE MACRO attr(attributes, key_name) AS
  list_extract(
    list_transform(
      list_filter(attributes, x -> x.key = key_name),
      x -> COALESCE(
        x.value.stringValue,
        CAST(x.value.intValue AS VARCHAR),
        CAST(x.value.doubleValue AS VARCHAR)
      )
    ),
    1
  );

-- Load raw OTLP JSON and flatten the 3-level hierarchy into log records.
CREATE TABLE raw AS
SELECT * FROM read_json_auto(getvariable('logs_path'), format='newline_delimited', union_by_name=true);

CREATE TABLE raw_logs AS
SELECT
  lr.body.stringValue AS event_type,
  epoch_ms((lr.timeUnixNano::BIGINT / 1000000)::BIGINT) AS event_time,
  lr.attributes AS attributes
FROM raw,
  UNNEST(raw.resourceLogs) AS t1(rl),
  UNNEST(rl.scopeLogs)     AS t2(sl),
  UNNEST(sl.logRecords)    AS t3(lr);

-- One row per tool_result, with the session and tool it belongs to.
-- IMPORTANT: tool_name also appears on tool_decision events; restrict to
-- tool_result so counts reflect actual completed tool calls.
CREATE TABLE tool_results AS
SELECT
  attr(attributes, 'session.id')  AS session_id,
  attr(attributes, 'tool_name')   AS tool_name,
  attr(attributes, 'success')     AS success,
  TRY_CAST(attr(attributes, 'duration_ms') AS BIGINT) AS duration_ms
FROM raw_logs
WHERE event_type = 'claude_code.tool_result'
  AND attr(attributes, 'session.id') IS NOT NULL;

-- Per-session boundaries and prompt/error counts across ALL event types.
CREATE TABLE session_span AS
SELECT
  attr(attributes, 'session.id') AS session_id,
  MIN(event_time) AS don_time,
  MAX(event_time) AS doff_time,
  ROUND(EXTRACT(EPOCH FROM (MAX(event_time) - MIN(event_time))) / 60.0, 1) AS duration_min,
  COUNT(*) FILTER (WHERE event_type = 'claude_code.user_prompt') AS n_prompts,
  COUNT(*) FILTER (WHERE event_type = 'claude_code.api_error')   AS n_api_errors
FROM raw_logs
WHERE attr(attributes, 'session.id') IS NOT NULL
GROUP BY 1;

-- Per-session API cost/token aggregates.
CREATE TABLE session_api AS
SELECT
  attr(attributes, 'session.id') AS session_id,
  COALESCE(SUM(TRY_CAST(attr(attributes, 'cost_usd') AS DOUBLE)), 0) AS cost_usd,
  COALESCE(SUM(TRY_CAST(attr(attributes, 'cache_read_tokens') AS BIGINT)), 0) AS cache_read_tokens,
  COALESCE(SUM(TRY_CAST(attr(attributes, 'input_tokens')  AS BIGINT)), 0)
    + COALESCE(SUM(TRY_CAST(attr(attributes, 'output_tokens') AS BIGINT)), 0) AS total_tokens
FROM raw_logs
WHERE event_type = 'claude_code.api_request'
  AND attr(attributes, 'session.id') IS NOT NULL
GROUP BY 1;

-- Per-session tool-mix aggregates (tool_result only).
CREATE TABLE session_tools AS
SELECT
  session_id,
  COUNT(*) AS n_tools,
  COUNT(*) FILTER (WHERE success = 'true')  AS n_tools_ok,
  COUNT(*) FILTER (WHERE success = 'false') AS n_tools_fail,
  COUNT(*) FILTER (WHERE tool_name = 'Read')  AS n_read,
  COUNT(*) FILTER (WHERE tool_name = 'Edit')  AS n_edit,
  COUNT(*) FILTER (WHERE tool_name = 'Write') AS n_write,
  COUNT(*) FILTER (WHERE tool_name = 'Bash')  AS n_bash,
  COUNT(*) FILTER (WHERE tool_name IN ('Grep','Glob'))            AS n_search,
  COUNT(*) FILTER (WHERE tool_name IN ('WebSearch','WebFetch'))   AS n_web,
  MEDIAN(duration_ms) AS tool_ms_p50,
  LIST(DISTINCT tool_name) AS tool_profile
FROM tool_results
GROUP BY 1;

-- Attribution per session from the sidecar map: how many DISTINCT masques were
-- donned in this session? 0 = baseline, 1 = clean masque, >1 = mixed (PRD D2).
CREATE TABLE session_attr AS
SELECT
  s.session_id,
  COUNT(DISTINCT a.masque) AS n_masques,
  -- the single masque name when clean; NULL for baseline or mixed
  CASE WHEN COUNT(DISTINCT a.masque) = 1 THEN MAX(a.masque) END AS masque
FROM session_span s
LEFT JOIN attribution a ON a.session_id = s.session_id
GROUP BY s.session_id;

-- Assemble the per-session row + derived fields.
CREATE TABLE sessions AS
WITH base AS (
  SELECT
    sp.session_id,
    sp.don_time, sp.doff_time,
    GREATEST(sp.duration_min, 0.1) AS duration_min,
    GREATEST(sp.n_prompts, 0) AS n_prompts,
    sp.n_api_errors,
    COALESCE(st.n_tools, 0) AS n_tools,
    COALESCE(st.n_tools_ok, 0) AS n_tools_ok,
    COALESCE(st.n_tools_fail, 0) AS n_tools_fail,
    COALESCE(st.n_read, 0)  AS n_read,
    COALESCE(st.n_edit, 0)  AS n_edit,
    COALESCE(st.n_write, 0) AS n_write,
    COALESCE(st.n_bash, 0)  AS n_bash,
    COALESCE(st.n_search,0) AS n_search,
    COALESCE(st.n_web, 0)   AS n_web,
    st.tool_ms_p50,
    COALESCE(st.tool_profile, []) AS tool_profile,
    COALESCE(sa.cost_usd, 0) AS cost_usd,
    COALESCE(sa.cache_read_tokens, 0) AS cache_read_tokens,
    COALESCE(sa.total_tokens, 0) AS total_tokens,
    am.masque,
    CASE
      WHEN am.n_masques = 0 THEN 'baseline'
      WHEN am.n_masques = 1 THEN 'clean'
      ELSE 'mixed'
    END AS attribution
  FROM session_span sp
  LEFT JOIN session_tools st ON st.session_id = sp.session_id
  LEFT JOIN session_api   sa ON sa.session_id = sp.session_id
  LEFT JOIN session_attr  am ON am.session_id = sp.session_id
),
ratios AS (
  SELECT *,
    GREATEST(n_tools, 1) AS tools_denom,
    (n_edit + n_write)::DOUBLE / GREATEST(n_tools, 1) AS change_share,
    (n_read + n_search)::DOUBLE / GREATEST(n_tools, 1) AS read_share,
    n_bash::DOUBLE / GREATEST(n_tools, 1) AS bash_share,
    n_web::DOUBLE  / GREATEST(n_tools, 1) AS web_share,
    n_tools_fail::DOUBLE / GREATEST(n_tools, 1) AS fail_rate
  FROM base
)
SELECT *,
  -- Heuristic task-class (PRD D5). Coarse and transparent; first match wins.
  -- Thresholds are tunable (OQ2). Works for baselines too — it reads only the
  -- tool mix, never the masque.
  CASE
    WHEN n_tools < 3 THEN 'unclassified'                              -- too little signal
    WHEN n_web >= 3 AND web_share >= 0.15 THEN 'research'             -- external lookup dominates
    WHEN change_share < 0.05 AND read_share >= 0.45 THEN 'review'     -- reading, not changing
    WHEN bash_share >= 0.5 AND change_share < 0.10 THEN 'ops'         -- command-running dominant
    WHEN fail_rate >= 0.06 AND n_bash >= 5 AND (n_edit + n_write) >= 1 THEN 'debug'  -- iterate w/ friction
    WHEN n_write >= 5 AND n_write >= n_edit AND change_share >= 0.15 THEN 'greenfield' -- creating files
    WHEN change_share >= 0.10 AND n_edit >= n_write THEN 'refactor'   -- modifying existing code
    ELSE 'unclassified'
  END AS task_class
FROM ratios;
