---
name: otel
description: Manage local OTEL collector for Claude Code telemetry
arguments:
  - name: action
    description: Action to perform (start, stop, status, config, logs)
    required: false
---

# OTEL Collector Command

Manage the local OpenTelemetry collector for capturing Claude Code telemetry.

**Arguments:** $ARGUMENTS

## Instructions

### Step 1: Parse Arguments

Extract the action from arguments (default: `status`):
- `start` - Build and start the collector
- `stop` - Stop the running collector
- `status` - Check if collector is running and healthy
- `config` - Show Claude Code configuration
- `logs` - Show collector logs

### Step 2: Execute Action

#### Action: `start`

1. Check if collector is already running:
```bash
docker ps --filter "name=masques-otel" --format "{{.Names}}"
```

2. If not running, build and start:
```bash
cd /Users/chris/git/masques/services/collector && docker build -t masques-collector . && docker run -d --name masques-otel -p 4317:4317 -p 4318:4318 -p 13133:13133 masques-collector
```

3. Wait for health check:
```bash
sleep 2 && curl -s http://localhost:13133/health
```

4. Report result:
```
✓ OTEL collector started
  gRPC: localhost:4317
  HTTP: localhost:4318
  Health: http://localhost:13133/health
```

#### Action: `stop`

1. Stop and remove the container:
```bash
docker stop masques-otel && docker rm masques-otel
```

2. Report result:
```
✓ OTEL collector stopped
```

If container doesn't exist, report:
```
✗ Collector not running
```

#### Action: `status`

1. Check if running:
```bash
docker ps --filter "name=masques-otel" --format "{{.Names}} {{.Status}}"
```

2. If running, check health:
```bash
curl -s http://localhost:13133/health
```

3. Report status:
```
OTEL Collector Status
─────────────────────
Container: running (Up 5 minutes)
Health: healthy
Endpoints:
  gRPC: localhost:4317
  HTTP: localhost:4318
```

Or if not running:
```
OTEL Collector Status
─────────────────────
Container: not running

Run /otel start to launch the collector.
```

#### Action: `config`

Show the Claude Code configuration needed:

```
Claude Code OTEL Configuration
──────────────────────────────

Add to ~/.claude/settings.json:

{
  "env": {
    "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
    "OTEL_METRICS_EXPORTER": "otlp",
    "OTEL_LOGS_EXPORTER": "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317"
  }
}

Or export as environment variables before running claude.

See docs/otel-setup.md for full documentation.
```

#### Action: `logs`

Show recent collector logs:
```bash
docker logs --tail 50 masques-otel
```

If container not running:
```
✗ Collector not running

Run /otel start to launch the collector.
```

## Error Handling

- If Docker is not running: report "Docker is not running. Start Docker Desktop and try again."
- If port already in use: report which port and suggest stopping conflicting service
- If build fails: show build error output
