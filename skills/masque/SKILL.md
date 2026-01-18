---
name: masque
description: Core skill for masque identity operations - reading masque definitions, extracting components, managing state
---

# Masque Operations Skill

This skill provides the core operations for working with masques.

## Masque Structure

A masque bundles five components:

1. **Intent** - What the masque is allowed/denied to do (glob patterns)
2. **Context** - Project and domain context
3. **Knowledge** - MCP URIs for knowledge lookups
4. **Access** - Credentials and permissions (vault role, TTL)
5. **Lens** - Cognitive framing and working style

## File Locations

- **Definitions:** `personas/*.masque.yaml` (source of truth)
- **Runtime JSON:** `entities/masques/*.masque.json` (for easy parsing)
- **State:** `.claude/masque.local.md` (active masque tracking)

## Reading a Masque

To load a masque, read from `entities/masques/<name>.masque.json`:

```json
{
  "name": "Chartwright",
  "version": "0.1.0",
  "ring": "player",
  "lens": "...",
  "context": "...",
  "intent": { "allowed": [...], "denied": [...] },
  "attributes": { "domain": "...", "stack": "...", "philosophy": "..." }
}
```

## State File Format

`.claude/masque.local.md` uses YAML frontmatter:

```yaml
---
active_masque: chartwright
version: "0.1.0"
donned_at: "2026-01-18T10:30:00Z"
ring: player
---

Masque Chartwright is active.
```

## Masque Injection Format

When a masque is active, inject its context using:

```
<masque-active name="Name" version="X.Y.Z" ring="ring">
[lens content]
[context content]
[intent boundaries]
</masque-active>
```

This format allows hooks to re-inject on session resume.

## Trust Rings

- **admin** - Full system access
- **player** - Standard development access
- **guest** - Read-only or limited scope
- **outsider** - Minimal trust, sandboxed

Rings determine continuous qualification, not just permissions.

## Intent Patterns

Intent uses glob-style matching:
- `implement visualization *` - matches any visualization task
- `modify backend *` - would match any backend modification

Denied patterns take precedence over allowed.
