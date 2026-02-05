# OTEL Setup for Claude Code

This guide explains how to configure Claude Code to send telemetry to a local OpenTelemetry collector.

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
docker build -t masques-collector .

# Run in foreground (see telemetry output)
docker run --rm -p 4317:4317 -p 4318:4318 -p 13133:13133 masques-collector
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
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```

Or add to your shell profile (`~/.zshrc`, `~/.bashrc`):

```bash
# Claude Code OTEL configuration
export CLAUDE_CODE_ENABLE_TELEMETRY=1
export OTEL_METRICS_EXPORTER=otlp
export OTEL_LOGS_EXPORTER=otlp
export OTEL_EXPORTER_OTLP_PROTOCOL=grpc
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317
```

### Option B: Claude Code Settings

Add to `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317"
  }
}
```

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
docker ps  # Should show masques-collector
netstat -an | grep 4317  # Should show LISTEN
```

### Using HTTP instead of gRPC

If gRPC doesn't work, try HTTP:
```bash
export OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
```

## Running in Background

For persistent operation:
```bash
docker run -d --name otel-collector \
  -p 4317:4317 -p 4318:4318 -p 13133:13133 \
  masques-collector

# View logs
docker logs -f otel-collector

# Stop
docker stop otel-collector && docker rm otel-collector
```

## What Gets Collected

Claude Code emits:
- **Metrics**: Tool usage counts, response times, token consumption
- **Logs**: Session events, errors, tool invocations

Note: Claude Code does **not** emit traces (spans). The collector config handles metrics and logs pipelines.

## Next Steps

Once you've verified data flows, you can:
- Add persistent storage (ClickHouse, PostgreSQL)
- Export to visualization tools (Grafana)
- Add alerting based on metrics

See `services/collector/config.yaml` for exporter configuration.
