#!/usr/bin/env bash
# judge.sh — DuckDB two-layer scoring for a captured session (PRD D4).
#
# Reads the collector's OTEL JSONL, enumerates every session (masque +
# baseline), classifies task-class, attributes masque cleanliness, and emits:
#   Layer A — a 7-point house reaction (always, from session one)
#   Layer B — lift vs the user's baseline corpus (only once earned)
#
# Usage: ./judge.sh [logs_path] [session_file]
#   logs_path     default: ../collector/data/logs.jsonl
#   session_file  default: .claude/masque.session.yaml (to read the active masque)
#
# Optional env:
#   TARGET_SESSION  score this session.id (default: most recent)
#   RUBRIC_BAND     Layer-A band from an LLM/Witness rubric judge (D7);
#                   one of perfect|great|good|neutral|bad|awful|detracting.
#                   Empty => activity fallback band.
#   BASELINE_MIN    baseline sessions per task_class before lift shows (default 5)
#   ATTRIBUTION     path to the session->masque sidecar map (JSONL).
#                   Default: ../collector/data/sessions.attribution.jsonl
#
# Requires: duckdb (brew install duckdb)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COLLECTOR_DIR="$(dirname "$SCRIPT_DIR")/collector"

LOGS_PATH="${1:-$COLLECTOR_DIR/data/logs.jsonl}"
SESSION_FILE="${2:-.claude/masque.session.yaml}"
ATTRIBUTION="${ATTRIBUTION:-$COLLECTOR_DIR/data/sessions.attribution.jsonl}"
TARGET_SESSION="${TARGET_SESSION:-}"
RUBRIC_BAND="${RUBRIC_BAND:-}"
BASELINE_MIN="${BASELINE_MIN:-5}"

# --- Preflight ---
if ! command -v duckdb &>/dev/null; then
  echo "error: duckdb not found — install: brew install duckdb" >&2
  exit 1
fi
if [[ ! -f "$LOGS_PATH" ]]; then
  echo "error: no logs at $LOGS_PATH" >&2
  echo "hint: seat the audience (/audience seat) and run a session" >&2
  exit 1
fi

# --- Attribution table prelude ---
# The sidecar map records which masque(s) were donned per session.id. It is
# written by /don (one line per don). If absent, we create an EMPTY table, so
# every session reads as baseline (masque=null) — the honest cold-start state.
if [[ -f "$ATTRIBUTION" ]]; then
  ATTR_SQL="CREATE TABLE attribution AS
    SELECT session_id, masque, donned_at
    FROM read_json_auto('${ATTRIBUTION}', format='newline_delimited', union_by_name=true);"
else
  ATTR_SQL="CREATE TABLE attribution(session_id VARCHAR, masque VARCHAR, donned_at VARCHAR);"
fi

# --- Run the pipeline ---
duckdb -noheader -list :memory: <<SQL
SET VARIABLE logs_path     = '${LOGS_PATH}';
SET VARIABLE target_session = '${TARGET_SESSION}';
SET VARIABLE rubric_band    = '${RUBRIC_BAND}';
SET VARIABLE baseline_min   = '${BASELINE_MIN}';

${ATTR_SQL}

.read ${SCRIPT_DIR}/sessions.sql
.read ${SCRIPT_DIR}/score.sql
SQL
