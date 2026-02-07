#!/usr/bin/env bash
# judge.sh — DuckDB performance scoring for masque sessions
#
# Reads OTEL JSONL from the collector's file exporter,
# extracts masque session boundaries, and scores performance
# across 5 dimensions. Outputs YAML to stdout.
#
# Usage: ./judge.sh [logs_path] [metrics_path]
#
# Requires: duckdb (brew install duckdb)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR_DIR="$(dirname "$SCRIPT_DIR")/collector"

LOGS_PATH="${1:-$COLLECTOR_DIR/data/logs.jsonl}"
METRICS_PATH="${2:-$COLLECTOR_DIR/data/metrics.jsonl}"
SESSION_FILE="${3:-.claude/masque.session.yaml}"

# --- Preflight checks ---

if ! command -v duckdb &>/dev/null; then
  echo "error: duckdb not found" >&2
  echo "install: brew install duckdb" >&2
  exit 1
fi

if [[ ! -f "$LOGS_PATH" ]]; then
  echo "error: no logs data at $LOGS_PATH" >&2
  echo "hint: start the collector with /audience start and run a session" >&2
  exit 1
fi

# --- Run scoring ---

# sessions.sql extracts masque session boundaries
# score.sql computes dimensions and composite score
# Both scripts reference $logs_path and $metrics_path via DuckDB variables

duckdb -noheader -csv :memory: <<SQL
-- Set paths as DuckDB variables
SET VARIABLE logs_path = '${LOGS_PATH}';
SET VARIABLE metrics_path = '${METRICS_PATH}';

.read ${SCRIPT_DIR}/sessions.sql
.read ${SCRIPT_DIR}/score.sql
SQL
