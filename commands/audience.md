---
name: audience
description: Manage the audience - telemetry observers watching your sessions
arguments:
  - name: action
    description: Action to perform (start, stop, status, config, logs)
    required: false
---

# Audience Command

Manage the audience — telemetry observers watching your performance. The audience sees everything: metrics, events, the full show.

**Arguments:** $ARGUMENTS

## Instructions

### Step 1: Parse Arguments

Extract the action from arguments (default: `status`):
- `start` - Invite the audience (start the collector)
- `stop` - Clear the house (stop the collector)
- `status` - Check if anyone's watching
- `config` - Show Claude Code configuration
- `logs` - Show what the audience has seen

### Step 2: Execute Action

#### Action: `start`

1. Check if audience is already seated:
```bash
docker ps --filter "name=masques-audience" --format "{{.Names}}"
```

2. If not present, start with docker compose:
```bash
cd /Users/chris/git/masques/services/collector && docker compose up -d
```

3. Wait for health check:
```bash
sleep 2 && curl -s http://localhost:13133/health
```

4. Report result:
```
✓ Audience seated
  gRPC: localhost:4317
  HTTP: localhost:4318
  Health: http://localhost:13133/health
```

If health check fails, suggest: "Port forwarding may not be working. Try `colima restart` if using Colima."

#### Action: `stop`

1. Stop with docker compose:
```bash
cd /Users/chris/git/masques/services/collector && docker compose down
```

2. Report result:
```
✓ Audience dismissed
```

If container doesn't exist, report:
```
✗ No audience present
```

#### Action: `status`

1. Check if running:
```bash
docker ps --filter "name=masques-audience" --format "{{.Names}} {{.Status}}"
```

2. If running, check health:
```bash
curl -s http://localhost:13133/health
```

3. Report status:
```
Audience Status
───────────────
Container: watching (Up 5 minutes)
Health: healthy
Endpoints:
  gRPC: localhost:4317
  HTTP: localhost:4318
```

Or if not running:
```
Audience Status
───────────────
Container: not present

Run /audience start to invite observers.
```

#### Action: `config`

Show the Claude Code configuration needed:

```
Claude Code Telemetry Configuration
───────────────────────────────────

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
cd /Users/chris/git/masques/services/collector && docker compose logs --tail 50
```

If container not running:
```
✗ No audience present

Run /audience start to invite observers.
```

## Error Handling

- If Docker is not running: report "Docker is not running. Start Docker Desktop and try again."
- If port already in use: report which port and suggest stopping conflicting service
- If build fails: show build error output
