#!/usr/bin/env bash
# captured.sh — count distinct sessions captured in the local audience record.
#
# Used by `/audience status` to answer "how many sessions has the house seen?"
# Reads the collector's OTLP JSONL and counts distinct session.id values.
# Every session — masque or baseline — carries a session.id, so this counts
# the whole captured corpus.
#
# Usage: ./captured.sh [logs_path]
# Output: a single integer on stdout (the distinct-session count).
# Exit:   0 on success; 2 if duckdb missing; 3 if no logs file.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR_DIR="$(dirname "$SCRIPT_DIR")/collector"
LOGS_PATH="${1:-$COLLECTOR_DIR/data/logs.jsonl}"

if ! command -v duckdb &>/dev/null; then
  echo "duckdb-missing" >&2
  exit 2
fi

if [[ ! -f "$LOGS_PATH" ]]; then
  echo "no-data" >&2
  exit 3
fi

duckdb -noheader -list :memory: <<SQL
CREATE MACRO attr(attributes, key_name) AS
  list_extract(
    list_transform(
      list_filter(attributes, x -> x.key = key_name),
      x -> COALESCE(x.value.stringValue, CAST(x.value.intValue AS VARCHAR))
    ), 1);
CREATE TABLE raw AS
  SELECT * FROM read_json_auto('${LOGS_PATH}', format='newline_delimited', union_by_name=true);
CREATE TABLE rl AS
  SELECT lr.attributes AS attributes
  FROM raw,
    UNNEST(raw.resourceLogs) AS t1(r),
    UNNEST(r.scopeLogs)      AS t2(s),
    UNNEST(s.logRecords)     AS t3(lr);
SELECT COUNT(DISTINCT attr(attributes, 'session.id'))
FROM rl
WHERE attr(attributes, 'session.id') IS NOT NULL;
SQL
