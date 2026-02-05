# Masque Schema Reference

A masque is a temporary cognitive identity bundling three components:
**lens** (cognitive framing), **context** (situational grounding), and **attributes** (metadata).

## Quick Reference

```yaml
name: string        # Required. Human-readable name
version: "x.y.z"    # Required. Semantic version

attributes:         # Optional. Flexible metadata
  domain: string
  tagline: string
  style: string
  philosophy: string

context: |          # Optional. Situational framing
  Who you're helping, what they value.

lens: |             # Required. Cognitive framing + intent guidance
  System prompt fragment.
  Include what to do, what to avoid, how to approach work.

spinnerVerbs:       # Optional. Custom spinner display
  mode: replace     # replace|append|prepend
  verbs:
    - "Masque:Verb..."
```

## Identity Fields

### name
Human-readable name for this masque. Used in logs, UI, and conversation.

### version
Semantic version string. Masques are pinned to versions; upgrading is deliberate.

## Attributes

Flexible key-value metadata. Common fields:

| Field | Description |
|-------|-------------|
| `domain` | What area this masque operates in |
| `tagline` | One-line summary of the masque's purpose |
| `style` | How the masque approaches work |
| `philosophy` | Core belief or principle |
| `stack` | Technologies this masque works with |

You can add any custom attributes your masques need.

## Spinner Verbs

Custom spinner text shown during agent activity:

```yaml
spinnerVerbs:
  mode: replace
  verbs:
    - "Codesmith:Forging..."
    - "Codesmith:Tempering..."
    - "Codesmith:Shaping..."
```

### Mode

| Mode | Behavior |
|------|----------|
| `replace` | Use only these verbs, replacing defaults |
| `append` | Add these verbs after the defaults |
| `prepend` | Add these verbs before the defaults |

Verbs use `Masque:Verb...` format (e.g., "Firekeeper:Tending...").

## Core Components

### Context

Domain knowledge and situational framing:

```yaml
context: |
  Building infrastructure for a small homelab.
  The human prioritizes stability over novelty.
  Budget is constrained; prefer open source.
```

Injected at assumption time. Provides cognitive grounding.

### Lens

System prompt fragment defining cognitive framing **and** intent guidance:

```yaml
lens: |
  You are a careful operator. When uncertain, ask.
  Prefer reversible changes. Document what you do.

  Boundaries:
  - Never delete production data without explicit approval.
  - Never rush deployments.
  - Never skip documentation.
```

The lens defines:
- How to think, what to prioritize
- Working style and approach
- What to avoid (boundaries)

Intent boundaries are now part of the lens as prose rather than separate glob patterns. This keeps everything in one place and reads more naturally.

## File Convention

Masque files use the `.masque.yaml` extension:

```
personas/
├── codesmith.masque.yaml
├── chartwright.masque.yaml
└── mirror.masque.yaml
```

## Validation

Validate masques against the schema using any YAML linter with JSON Schema support.

The formal schema is at `schemas/masque.schema.yaml`.

## Example

See `personas/codesmith.masque.yaml` for a complete example.
