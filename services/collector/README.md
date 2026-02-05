# Local OTEL Collector

Minimal OpenTelemetry collector for receiving Claude Code telemetry locally.

## Quick Start

```bash
# Build
docker build -t masques-collector .

# Run (foreground, see telemetry in logs)
docker run --rm -p 4317:4317 -p 4318:4318 -p 13133:13133 masques-collector

# Health check
curl http://localhost:13133/health
```

## Ports

| Port  | Protocol | Purpose |
|-------|----------|---------|
| 4317  | gRPC     | OTLP gRPC receiver |
| 4318  | HTTP     | OTLP HTTP receiver |
| 13133 | HTTP     | Health check endpoint |

## What It Does

- Receives OTLP metrics and logs on standard ports
- Batches incoming data (5s timeout, 256 batch size)
- Logs everything to stdout with detailed verbosity

## Configuration

Edit `config.yaml` to:
- Add exporters (ClickHouse, Jaeger, etc.)
- Adjust batch settings
- Enable additional pipelines (traces)

See [docs/otel-setup.md](../../docs/otel-setup.md) for Claude Code configuration.
