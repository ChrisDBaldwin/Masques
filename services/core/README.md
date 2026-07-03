# masques-core

The portable Masques core: resolve and compose a **Persona** — a pinned
cognitive identity (`<name>.masque.yaml`) plus an optional mutable operational
sidecar (`<name>.persona.yaml`) — with zero infrastructure. PyYAML is the only
dependency.

This package is what makes masques "slap on top of any agent": hosts (the
Claude Code plugin's MCP server, [loon-agent](https://github.com/ChrisDBaldwin),
a CLI) are thin adapters over these pure functions.

```python
import masques_core as mc

persona = mc.resolve("codesmith")            # Identity + sidecar, no I/O beyond YAML
payload = mc.compose(persona, intent="ship the parser")
payload["identity_block"]                     # the <masque-active> block a host injects

plan, bound_refs = mc.build_capability_plan(  # pure fold; honesty wired into the data
    persona, mc.HostSnapshot(servers=frozenset({"host"}), achievable_tier="bind")
)
```

Design: `docs/design/phase1-data-model.md` (entities), `phase2-core-api.md`
(function contracts), `phase3-portable-core.md` (this package + reference
hosts) in the repo root.

## Layout

- `model.py` — Persona aggregate, Identity, Version/PersonaRef, sidecar
  value-objects (CredentialBinding/SecretRef, McpBinding, MeasurementPolicy),
  CapabilityPlan/BoundRef
- `core.py` — `resolve` / `compose` / `build_identity_block` /
  `build_capability_plan` / `list_masques` / `inspect` — all pure
- `sidecar.py` — sidecar parsing + in-aggregate validation (rejects inline
  secrets and free-form config strings; enforces alias↔audience symmetry)
- `ports.py` — SecretPort/McpPort/TelemetryPort Protocols, registry, and the
  dependency-free default adapters (Env, Advisory, Null)
- `schemas/` — masque.schema.yaml as package data

## Guarantees

- **A fresh don touches zero adapters.** `resolve`/`compose` never resolve a
  secret, contact a server, or read telemetry.
- **A malformed sidecar degrades, never denies the don** — `config=None` plus
  a surfaced `config_error` warning.
- **No secret material, ever** — in any returned dict, repr, or mirror; only
  `alias + scheme + status` references travel.
- **Enforcement honesty in the data** — advisory allow/deny lists are named
  `advisory_*`; `effective_*` and `enforced: true` appear only when a host
  actually mediates the tool boundary.

## Develop

```bash
cd services/core
uv sync --extra dev
uv run pytest
```
