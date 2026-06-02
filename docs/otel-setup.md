# OTEL Setup — Seating the Always-On Audience

This guide seats the **persistent audience**: a local OpenTelemetry collector
that captures *every* Claude Code session — masque or baseline — to local JSONL.
You seat it **once**; Docker keeps it alive across crashes and reboots. There is
no per-session start (PRD D1).

> **Quick start:** `/audience seat` does all of Step 1–2 for you and verifies
> the result. This document is the manual / reference version.

## Why always-on

The audience can only baseline a masque against "no masque" if it has been
watching all along. Summoning a collector per session can't accrue a baseline
corpus. So the collector is seated once and left running; the record of
baseline sessions builds itself, and lift ("Codesmith vs your baseline on
refactor work") becomes computable. See `docs/evaluation.md`.

## Privacy posture (read this first)

The collector is **local-only by default**. Its only sinks are a debug console
and local JSONL files under `services/collector/data/`. **Nothing leaves the
machine.** Forwarding to a remote (masques.ai / ClickHouse, Tier 3) is **opt-in
and disabled** — it lives commented-out in `config.yaml` and is deferred work.
Note the local JSONL *does* contain raw prompt/tool content; that is fine
locally, but it is exactly why forwarding must ship only the derived Tier-2
signal, never this raw file (PRD D3).

## Prerequisites

- Docker installed and running — and set to **start on login** (Docker Desktop →
  Settings → General). This is what makes the audience survive a reboot.
- Claude Code installed.
- DuckDB for scoring: `brew install duckdb`.

## Step 1: Seat the collector (once)

```bash
cd services/collector
docker compose up -d --build
```

`docker-compose.yml` pins `restart: unless-stopped` and a healthcheck that
probes the `:13133` health endpoint, so a crashed *or hung* collector is
restarted automatically. Verify:

```bash
docker compose ps                  # masques-audience → Up (healthy)
curl -s http://localhost:13133/    # → {"status":"Server available",...}
```

You do **not** run this per session. Once it is up, Docker re-seats it after
reboots on its own.

## Step 2: Configure Claude Code telemetry (once)

Add to `~/.claude/settings.json` (then restart `claude` so it takes effect):

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/protobuf",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4318",
    "OTEL_LOG_TOOL_DETAILS": "1"
  }
}
```

(Equivalently, `export` these in your shell profile before launching `claude`.)

> **`OTEL_LOG_TOOL_DETAILS=1`** enriches tool events. The richer the tool
> events, the better the heuristic task-class inference and scoring.

Telemetry env is read at `claude` startup — a session already running won't be
captured until it restarts.

## Step 3: Verify capture

Open a new Claude Code session, do a little work, then:

```bash
# How many sessions has the house captured? (distinct session.id)
./services/judge/captured.sh

# Watch live capture
cd services/collector && docker compose logs -f
```

Every session writes events tagged with a `session.id`; the judge uses that as
the session boundary (`don_time` = first event, `doff_time` = last). Baseline
sessions (no `/don`) are captured exactly the same way — they simply carry no
masque attribution.

## How masque vs baseline is distinguished

The telemetry stream itself has no masque field. Attribution is added by `/don`,
which appends one line to a **local sidecar map**,
`services/collector/data/sessions.attribution.jsonl`:

```json
{"session_id":"<CLAUDE_CODE_SESSION_ID>","masque":"Codesmith","donned_at":"..."}
```

`CLAUDE_CODE_SESSION_ID` equals the telemetry `session.id`, so the judge joins
the two cleanly. A session with no line is a **baseline** sample; one line is a
**clean** masque sample; two+ distinct masques in one session is **mixed** and
excluded from lift (PRD D2). This sidecar is local attribution metadata and is
never forwarded.

## What gets collected

Claude Code emits **metrics** and **logs** (events) over OTLP — no traces. The
log events that matter for scoring:

- `claude_code.tool_result` — `tool_name`, `success`, `duration_ms`
- `claude_code.user_prompt` — user turns
- `claude_code.api_request` — `cost_usd`, token counts, cache stats
- `claude_code.api_error` — friction signal

## Scoring

```bash
./services/judge/judge.sh          # most recent session
TARGET_SESSION="$CLAUDE_CODE_SESSION_ID" ./services/judge/judge.sh   # this session
# or the plugin command:
/performance
```

Output is the two-layer reaction (Layer A always; Layer B lift once earned).
See `docs/evaluation.md` for the model.

## Troubleshooting

**Collector won't stay up / crash-loops.** In v1.1 the default config is
local-only and has no remote dependency, so it should not crash-loop. If you
opted into ClickHouse forwarding and the remote is down, that can wedge startup
— disable it (re-comment the `clickhouse` exporter in `config.yaml`) and rebuild.

**No telemetry appearing.**
1. `CLAUDE_CODE_ENABLE_TELEMETRY=1` set, and `claude` restarted since.
2. Collector healthy: `curl http://localhost:13133/`.
3. Endpoint reachable: HTTP `:4318` (or gRPC `:4317`).

**Use gRPC instead of HTTP:**
```bash
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```

## Dismissing the audience

Rare — you normally leave it seated. To close the house entirely:

```bash
cd services/collector && docker compose down   # or: /audience dismiss
```

## Deferred (not in v1.1)

- A **no-Docker, zero-infra** capture path (native `otelcol` as a launchd
  service, a purpose-built local OTLP receiver, or a direct OTEL file sink) —
  friction reduction on the always-on loop (PRD OQ1).
- **Forwarding** the derived Tier-2 signal to masques.ai (Tier 3) — opt-in,
  privacy-gated, Phase 4.
