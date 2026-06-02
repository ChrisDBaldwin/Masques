---
name: audience
description: Manage the audience - the always-on observer watching your sessions
arguments:
  - name: action
    description: Action to perform (seat, dismiss, status, logs)
    required: false
---

# Audience Command

The audience is the always-on observer that watches every session — masque or
baseline — and scores it. Unlike a per-session summon, **the audience is seated
once and left running**: Docker keeps the collector alive across crashes and
reboots, so capture is ambient. You do not start it per session.

**Arguments:** $ARGUMENTS

## Lifecycle (mental model)

```
seat ──▶ (house open, capturing every session, survives reboot) ──▶ dismiss
            │
            └─▶ status / logs  (peek without disturbing the house)
```

You run `seat` **once** (first-time setup). After that the house stays open on
its own. `dismiss` is the rare "close the house entirely" action — you normally
leave it seated.

## Instructions

### Step 1: Parse Arguments

Extract the action from arguments (default: `status`):
- `seat` — open the house once (start the persistent collector + verify telemetry env)
- `dismiss` — close the house entirely (stop the collector; capture stops)
- `status` — is the house open? how many sessions captured?
- `logs` — show what the audience has seen (recent collector logs)

`start`/`stop` are accepted as deprecated aliases for `seat`/`dismiss` — when
used, do the action but note the rename, because the old "start per session"
ritual no longer applies (the house stays open).

### Step 2: Execute Action

#### Action: `seat`

Seat the audience **once**. This is setup, not a per-session step.

1. Check if the audience is already seated:
```bash
docker ps --filter "name=masques-audience" --format "{{.Names}} {{.Status}}"
```
If it is already `Up`, say so and skip to verifying telemetry env (step 3) —
seating is idempotent; do not recreate a healthy house.

2. If not present, seat it (build + start as a persistent, restart-on-failure
service):
```bash
cd ${CLAUDE_PLUGIN_ROOT}/services/collector && docker compose up -d --build
```
The compose file pins `restart: unless-stopped` and a `:13133` healthcheck, so a
crashed *or hung* collector is restarted automatically. Nothing leaves the
machine — the default config writes only local JSONL (see docs/otel-setup.md).

3. Verify the house is healthy:
```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:13133/
```
`200` = healthy.

4. **Verify Claude Code telemetry env is set** (capture is silent if it isn't).
Check `~/.claude/settings.json` for the telemetry block:
```bash
grep -q CLAUDE_CODE_ENABLE_TELEMETRY ~/.claude/settings.json && echo "env: configured" || echo "env: MISSING"
```
If MISSING, tell the user to add this to `~/.claude/settings.json` (then restart
`claude` so it takes effect):
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
`OTEL_LOG_TOOL_DETAILS=1` enriches tool events (needed for task-class inference
and scoring). Note: telemetry env applies at `claude` startup — a session
already running won't be captured until it restarts.

5. Remind the user to make the house survive reboots: ensure Docker Desktop is
set to **start on login** (Docker Desktop → Settings → General → "Start Docker
Desktop when you sign in"). With that, `restart: unless-stopped` re-seats the
audience automatically after a reboot — no re-run of `seat`.

6. Report:
```
✓ Audience seated — the house is open
  Capture:  every session (masque + baseline) → local JSONL
  Health:   http://localhost:13133/ (200)
  Endpoints: gRPC localhost:4317 · HTTP localhost:4318
  Telemetry env: configured
  Persistence: restart: unless-stopped (survives crash/reboot if Docker starts on login)

  Seated once — you do not need to run this again per session.
```

If health check fails, suggest: "Port forwarding may not be up. If using Colima,
try `colima restart`. Check `/audience logs` for startup errors."

#### Action: `dismiss`

Close the house entirely. Capture stops until you `seat` again — normally you
leave the audience seated, so confirm intent.

```bash
cd ${CLAUDE_PLUGIN_ROOT}/services/collector && docker compose down
```
Report:
```
✓ Audience dismissed — the house is closed. No sessions will be captured until
  you run /audience seat again.
```
If the container doesn't exist, report `✗ No audience present (already closed)`.

#### Action: `status`

Report whether the house is open and how much it has captured.

1. Is the house open?
```bash
docker ps --filter "name=masques-audience" --format "{{.Status}}"
```
2. If open, confirm health:
```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:13133/
```
3. How many sessions captured? (counts distinct session.id across the local
record — masque and baseline alike):
```bash
${CLAUDE_PLUGIN_ROOT}/services/judge/captured.sh
```
This prints an integer. If it exits non-zero: exit 2 → "duckdb not installed
(brew install duckdb) — count unavailable"; exit 3 → "no telemetry captured yet".

4. Report (house open):
```
Audience Status
───────────────
House:    OPEN  (Up 3 days, healthy)
Captured: 68 sessions in the local record
Telemetry env: configured
Local sink: services/collector/data/logs.jsonl

The audience is always seated — capture is ambient, no per-session start.
```
Or (house closed):
```
Audience Status
───────────────
House:    CLOSED (collector not running)
Captured: 68 sessions in the local record (from earlier)

Run /audience seat to open the house. It stays open after that.
```

#### Action: `logs`

Show recent collector logs:
```bash
cd ${CLAUDE_PLUGIN_ROOT}/services/collector && docker compose logs --tail 50
```
If the container isn't running, report `✗ House is closed — run /audience seat`.

## Error Handling

- Docker not running: "Docker is not running. Start Docker Desktop (and enable
  start-on-login so the audience stays seated), then `/audience seat`."
- Port already in use: report which port and the conflicting service.
- Build fails: show the build error output.
- The collector is **local-only by default** — it never depends on a remote, so
  it should not crash-loop. Remote forwarding to masques.ai (Tier 3) is opt-in
  and disabled by default; see config.yaml and docs/otel-setup.md.

## What changed from the old `/audience`

The previous command treated the collector as a per-session summon
(`start`/`stop`, run each time). v1.1 inverts this: the audience is **seated
once and always on** (PRD D1) so the baseline corpus accrues without ritual.
`seat`/`dismiss` replace `start`/`stop`; `status` now also reports the captured
session count.
