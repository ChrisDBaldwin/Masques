-- sessions.sql — Extract masque session boundaries from OTEL log events
--
-- Reads logs.jsonl (OTLP JSON) and flattens the nested structure:
--   resourceLogs[].scopeLogs[].logRecords[]
--
-- Each logRecord has:
--   body.stringValue  → event type (e.g. "claude_code.tool_result")
--   attributes[]      → array of {key, value: {stringValue|intValue}} objects
--
-- Session is identified by session.id attribute. Masque name comes from
-- the session YAML file, passed as DuckDB variable `masque_name`.
--
-- Output: table `masque_sessions` with columns:
--   masque_name, session_id, don_time, doff_time, duration_min

-- Helper: extract a string attribute from the OTLP attributes array
CREATE MACRO attr(attributes, key_name) AS
  list_extract(
    list_transform(
      list_filter(attributes, x -> x.key = key_name),
      x -> COALESCE(x.value.stringValue, CAST(x.value.intValue AS VARCHAR))
    ),
    1
  );

-- Load raw OTLP JSON
CREATE TABLE raw AS
SELECT * FROM read_json_auto(getvariable('logs_path'), format='newline_delimited', union_by_name=true);

-- Flatten the 3-level OTLP hierarchy into individual log records
CREATE TABLE raw_logs AS
SELECT
  lr.body.stringValue AS event_type,
  lr.timeUnixNano::BIGINT AS timestamp_ns,
  epoch_ms((lr.timeUnixNano::BIGINT / 1000000)::BIGINT) AS event_time,
  lr.attributes AS attributes
FROM raw,
  UNNEST(raw.resourceLogs) AS t1(rl),
  UNNEST(rl.scopeLogs) AS t2(sl),
  UNNEST(sl.logRecords) AS t3(lr);

-- Build session from session.id attribute + masque name variable
CREATE TABLE masque_sessions AS
SELECT
  getvariable('masque_name') AS masque_name,
  attr(attributes, 'session.id') AS session_id,
  MIN(event_time) AS don_time,
  MAX(event_time) AS doff_time,
  ROUND(
    EXTRACT(EPOCH FROM (MAX(event_time) - MIN(event_time))) / 60.0,
    1
  ) AS duration_min
FROM raw_logs
WHERE attr(attributes, 'session.id') IS NOT NULL
GROUP BY attr(attributes, 'session.id');
