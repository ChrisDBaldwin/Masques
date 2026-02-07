-- sessions.sql — Extract masque session boundaries from OTEL log events
--
-- Reads logs.jsonl and identifies don/doff events from tool_result records
-- where skill_name = 'don' or 'doff' (requires OTEL_LOG_TOOL_DETAILS=1).
--
-- Output: temp table `masque_sessions` with columns:
--   masque_name, don_time, doff_time, duration_min

-- Load raw log events from JSONL
CREATE TABLE raw_logs AS
SELECT * FROM read_json_auto(getvariable('logs_path'), format='newline_delimited', union_by_name=true);

-- Extract masque don/doff events from tool_result log records
-- The OTEL file exporter writes OTLP JSON with resourceLogs structure.
-- Claude Code tool_result events include tool name and skill_name in attributes.
--
-- NOTE: The exact JSON structure from the file exporter needs validation
-- against real collector output. These paths are best-effort based on the
-- OTLP JSON encoding spec. Phase 1: get data flowing. Phase 2: tune paths.
CREATE TABLE masque_events AS
SELECT
  body::JSON->>'stringValue' as event_body,
  timeUnixNano::BIGINT as timestamp_ns,
  epoch_ms(timeUnixNano::BIGINT / 1000000) as event_time,
  -- Try multiple possible attribute paths for skill_name
  COALESCE(
    json_extract_string(attributes, '$[?(@.key=="skill_name")].value.stringValue'),
    json_extract_string(body::JSON, '$.skill_name'),
    'unknown'
  ) as skill_name,
  -- Try to extract masque name from event body or attributes
  COALESCE(
    json_extract_string(body::JSON, '$.masque_name'),
    json_extract_string(attributes, '$[?(@.key=="masque_name")].value.stringValue'),
    'unknown'
  ) as masque_name
FROM raw_logs
WHERE
  -- Look for Skill tool calls that are don or doff
  COALESCE(
    json_extract_string(attributes, '$[?(@.key=="skill_name")].value.stringValue'),
    json_extract_string(body::JSON, '$.skill_name'),
    ''
  ) IN ('don', 'doff');

-- Build session windows by pairing don → doff events
CREATE TABLE masque_sessions AS
WITH ordered_events AS (
  SELECT
    *,
    ROW_NUMBER() OVER (ORDER BY timestamp_ns) as rn,
    LEAD(event_time) OVER (ORDER BY timestamp_ns) as next_event_time,
    LEAD(skill_name) OVER (ORDER BY timestamp_ns) as next_skill
  FROM masque_events
)
SELECT
  masque_name,
  event_time as don_time,
  COALESCE(
    CASE WHEN next_skill = 'doff' THEN next_event_time END,
    now()  -- session still active
  ) as doff_time,
  ROUND(
    EXTRACT(EPOCH FROM (
      COALESCE(
        CASE WHEN next_skill = 'doff' THEN next_event_time END,
        now()
      ) - event_time
    )) / 60.0,
    1
  ) as duration_min
FROM ordered_events
WHERE skill_name = 'don';

-- If no don/doff events found in logs, fall back to a single "current session"
-- window covering all events in the log file
INSERT INTO masque_sessions
SELECT
  'unknown' as masque_name,
  MIN(epoch_ms(timeUnixNano::BIGINT / 1000000)) as don_time,
  MAX(epoch_ms(timeUnixNano::BIGINT / 1000000)) as doff_time,
  ROUND(
    EXTRACT(EPOCH FROM (
      MAX(epoch_ms(timeUnixNano::BIGINT / 1000000)) -
      MIN(epoch_ms(timeUnixNano::BIGINT / 1000000))
    )) / 60.0,
    1
  ) as duration_min
FROM raw_logs
WHERE NOT EXISTS (SELECT 1 FROM masque_events LIMIT 1);
