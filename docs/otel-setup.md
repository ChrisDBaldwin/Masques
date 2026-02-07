# OTEL Setup for Claude Code

This guide explains how to configure Claude Code to send telemetry to a local OpenTelemetry collector.

> **Quick Start**: Use `/audience start` to launch the collector with a single command.

## Overview

Claude Code emits **metrics** and **logs** (events) via OTLP. This setup:
1. Runs a local OTEL collector in Docker
2. Configures Claude Code to send telemetry to it
3. Displays telemetry in the collector's console output

## Prerequisites

- Docker installed and running
- Claude Code installed

## Step 1: Start the Collector

```bash
cd services/collector

# Build the image
docker build -t masques-audience .

# Run in foreground (see telemetry output)
docker run --rm -p 4317:4317 -p 4318:4318 -p 13133:13133 masques-audience
```

Verify it's running:
```bash
curl http://localhost:13133/health
# Should return: {"status":"Server available","upSince":"...","uptime":"..."}
```

## Step 2: Configure Claude Code

### Option A: Environment Variables

Set these before running `claude`:

```bash
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_LOG_TOOL_DETAILS=1
```

Or add to your shell profile (`~/.zshrc`, `~/.bashrc`):

```bash
# Claude Code OTEL configuration
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
export OTEL_LOG_TOOL_DETAILS=1
```

### Option B: Claude Code Settings

Add to `~/.claude/settings.json`:

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

> **`OTEL_LOG_TOOL_DETAILS=1`** enables `skill_name` in tool events, which is required for `/performance` to detect masque don/doff session boundaries in the telemetry stream.

## Step 3: Verify

1. Start the collector (Step 1)
2. Open a new Claude Code session
3. Watch the collector output for telemetry data

You should see metrics and log events flowing through:
```
2024-01-26T12:00:00.000Z info LogsExporter {"kind": "exporter", "data_type": "logs", ...}
2024-01-26T12:00:00.000Z info MetricsExporter {"kind": "exporter", "data_type": "metrics", ...}
```

## Troubleshooting

### No telemetry appearing

1. Check `CLAUDE_CODE_ENABLE_TELEMETRY=1` is set
2. Verify collector is running: `curl http://localhost:13133/health`
3. Check port 4317 isn't blocked or in use

### Connection refused

Ensure the collector started successfully and ports are exposed:
```bash
docker ps  # Should show masques-audience
netstat -an | grep 4317  # Should show LISTEN
```

### Using gRPC instead of HTTP

If HTTP/protobuf doesn't work, try gRPC:
```bash
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```

## Running in Background

For persistent operation, use `/audience start` or manually:
```bash
docker run -d --name masques-audience \
  -p 4317:4317 -p 4318:4318 -p 13133:13133 \
  masques-audience

# View logs
docker logs -f masques-audience

# Stop
docker stop masques-audience && docker rm masques-audience
```

## What Gets Collected

Claude Code emits:
- **Metrics**: Tool usage counts, response times, token consumption
- **Logs**: Session events, errors, tool invocations

Note: Claude Code does **not** emit traces (spans). The collector config handles metrics and logs pipelines.

## Performance Scoring

The collector writes JSONL files to `services/collector/data/` alongside shipping to ClickHouse. The DuckDB judge (`services/judge/`) reads this local data to score masque sessions.

```bash
# Run performance scoring directly
./services/judge/judge.sh

# Or use the plugin command
/performance
```

The judge scores 5 dimensions — Quality, Autonomy, Productivity, Token Efficiency, Cost Efficiency — and produces a composite score with a keep/review/doff recommendation.

Requires:
- DuckDB installed (`brew install duckdb`)
- `OTEL_LOG_TOOL_DETAILS=1` for masque session detection
- Telemetry data in `services/collector/data/logs.jsonl`

## Next Steps

Once you've verified data flows, you can:
- Run `/performance` to score your masque sessions
- Add persistent storage (ClickHouse, PostgreSQL)
- Export to visualization tools (Grafana)
- Add alerting based on metrics

See `services/collector/config.yaml` for exporter configuration.
