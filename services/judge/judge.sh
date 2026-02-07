#!/usr/bin/env bash
# judge.sh — DuckDB performance scoring for masque sessions
#
# Reads OTEL JSONL from the collector's file exporter,
# extracts masque session boundaries, and scores performance
# across 5 dimensions. Outputs YAML to stdout.
#
# Usage: ./judge.sh [logs_path] [session_file]
#
# Requires: duckdb (brew install duckdb)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR_DIR="$(dirname "$SCRIPT_DIR")/collector"

LOGS_PATH="${1:-$COLLECTOR_DIR/data/logs.jsonl}"
SESSION_FILE="${2:-.claude/masque.session.yaml}"

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

# --- Extract masque name from session YAML ---

MASQUE_NAME="unknown"
if [[ -f "$SESSION_FILE" ]]; then
  MASQUE_NAME=$(grep '^ *name:' "$SESSION_FILE" | head -1 | sed 's/^ *name: *//')
fi

# --- Run scoring ---

# sessions.sql flattens OTLP hierarchy and builds session windows
# score.sql computes dimensions and composite score

duckdb -noheader -csv :memory: <<SQL
SET VARIABLE logs_path = '${LOGS_PATH}';
SET VARIABLE masque_name = '${MASQUE_NAME}';

.read ${SCRIPT_DIR}/sessions.sql
.read ${SCRIPT_DIR}/score.sql
SQL
