# Implementation

Masques should not be documentation (`.md` files). They should be **the smallest programs that efficiently power the system**.

## Masques as Programs

A masque is executable code that produces:

- Intent validation
- Context injection
- Knowledge pointers (MCP URIs)
- Access tokens (minted or fetched)
- Lens (system prompt fragment)

This can be full code or a declarative DSL that compiles to runnable code.

## Full Code Approach

```python
# masque/homelab.py
class Homelab(Masque):
    version = "2.3"
    ring_required = Ring.PLAYER

    def validate_intent(self, intent: str) -> bool:
        allowed = ["deploy *", "debug *", "investigate *"]
        denied = ["delete *", "destroy *"]
        return matches_patterns(intent, allowed, denied)

    def knowledge(self) -> list[str]:
        return [
            "mcp://homelab-inventory",
            "mcp://homelab-runbooks"
        ]

    def access(self, session: Session) -> Credentials:
        return vault.mint_temporary(
            "homelab-operator",
            ttl=session.duration
        )

    def lens(self) -> str:
        return """You're operating Chris's homelab.
        Prefer stability over novelty. When uncertain, ask.
        Document what you do."""
```

Benefits:
- Full programmatic control
- Dynamic behavior based on context
- Integration with existing systems
- Type safety and IDE support

## Declarative DSL Approach

```yaml
# masque/homelab.masque.yaml
name: Homelab
version: "2.3"
ring: player

intent:
  allowed: ["deploy *", "debug *", "investigate *"]
  denied: ["delete *", "destroy *"]

knowledge:
  - mcp://homelab-inventory
  - mcp://homelab-runbooks

access:
  vault_role: homelab-operator
  ttl: session

lens: |
  You're operating Chris's homelab.
  Prefer stability over novelty. When uncertain, ask.
  Document what you do.
```

Benefits:
- Readable by non-programmers
- Easy to review in PRs
- Validatable against schema
- Portable across runtimes

## Current Format

The current format is `.masque.yaml`—a declarative DSL. See [schema.md](schema.md) for the full specification.

The Zig runtime validates these files against `schemas/masque.schema.yaml`.

## Runtime Responsibilities

The masque runtime (Zig implementation in progress) provides:

### YAML Parsing and Validation

```bash
# Validate a masque definition
masque validate personas/codesmith.masque.yaml
```

### Intent Pattern Matching

Glob-style patterns for allowed/denied intents:

```yaml
intent:
  allowed: ["implement *", "test *"]
  denied: ["rush *", "delete production *"]
```

Denied takes precedence over allowed.

### MCP URI Resolution

Knowledge pointers resolve to actual MCP servers:

```
mcp://homelab-inventory → localhost:8080/inventory
mcp://homelab-runbooks  → localhost:8080/runbooks
```

### Session Management

The don/doff lifecycle:

```bash
# Don a masque
claude assume masque:homelab@v2.3 --intent "deploying monitoring"

# Session active... work happens...

# Doff (automatic on session end, or explicit)
claude release
```

### Credential Minting

Access configuration becomes actual credentials:

```yaml
access:
  vault_role: homelab-operator
  ttl: session
```

Becomes a call to Vault (or equivalent) to mint a temporary token.

### Reflection Queries

DuckDB-backed queries across all masque sessions:

```bash
# How is this masque performing?
masque stats homelab

# How are all Zig-skilled masques performing?
masque stats --skill zig
```

## Directory Structure

```
masque/
├── schemas/
│   └── masque.schema.yaml    # JSON Schema for validation
├── personas/                  # Masque definitions
│   ├── codesmith.masque.yaml
│   ├── homelab.masque.yaml
│   └── reviewer.masque.yaml
└── src/                       # Zig runtime
    ├── main.zig
    └── root.zig
```

## File Convention

Masque files use the `.masque.yaml` extension and live in `personas/`:

```bash
personas/codesmith.masque.yaml
personas/homelab.masque.yaml
personas/reviewer.masque.yaml
```

This keeps masque definitions separate from runtime code and documentation.
