# Masque Schema Reference

A masque is a temporary cognitive identity bundling five components:
**intent**, **context**, **knowledge**, **access**, and **lens**.

## Quick Reference

```yaml
name: string        # Required. Human-readable name
index: integer      # Required. Unique numeric ID (>= 1)
version: "x.y.z"    # Required. Semantic version

ring: player        # Required. admin|player|guest|outsider

attributes:         # Optional. Flexible metadata
  key: value

skills:             # Optional. External skill references
  - uri: skill://domain/name
    level: competent

intent:             # Required. What this masque can do
  allowed: ["implement *"]
  denied: ["rush *"]

context: |          # Optional. Situational framing
  Who you're helping, what they value.

knowledge:          # Optional. MCP pointers
  - mcp://server/resource

access:             # Optional. Credential config
  vault_role: role-name
  ttl: session

lens: |             # Required. Cognitive framing
  System prompt fragment.

performance:        # Optional. Contribution evaluation
  score: "*"
  history: []
```

## Identity Fields

### name
Human-readable name for this masque. Used in logs, UI, and conversation.

### index
Unique numeric identifier. Starts at 1. Used for registry lookups.

### version
Semantic version string. Masques are pinned to versions; upgrading is deliberate.

## Trust Ring

```yaml
ring: admin|player|guest|outsider
```

Determines who can assume this masque. See [trust-rings.md](trust-rings.md) for full model.

| Ring | Qualification |
|------|---------------|
| admin | Full system access, highest accountability |
| player | Invested contributor, aligned incentives |
| guest | Supervised, scoped, explicitly temporary |
| outsider | No trust relationship, public access only |

## Skills

Reference external skill definitions with claimed proficiency:

```yaml
skills:
  - uri: skill://programming/zig
    level: competent
```

### Skill Levels

| Level | Meaning |
|-------|---------|
| novice | Learning, needs guidance |
| competent | Standard tasks independently |
| proficient | Complex cases, teaches others |
| expert | Deep mastery, defines best practices |
| master | Shapes the field, creates new approaches |

Skills are **claims** rated against actual performance.

## The Five Components

### 1. Intent

What the masque is allowed to do:

```yaml
intent:
  allowed:
    - "implement *"
    - "test *"
  denied:
    - "delete production *"
```

Glob patterns. Denied takes precedence over allowed.

### 2. Context

Domain knowledge and situational framing:

```yaml
context: |
  Building infrastructure for a small homelab.
  The human prioritizes stability over novelty.
  Budget is constrained; prefer open source.
```

Injected at assumption time. Provides cognitive grounding.

### 3. Knowledge

MCP URIs for runtime knowledge lookup:

```yaml
knowledge:
  - mcp://homelab/inventory
  - mcp://homelab/runbooks
```

**Pointers, not blobs.** Masques stay lightweight; knowledge is fresh at source.

### 4. Access

Credential configuration:

```yaml
access:
  vault_role: homelab-operator
  ttl: session
```

- `vault_role`: Role to assume for credential minting
- `ttl`: `session` (expires when masque is doffed) or ISO 8601 duration

### 5. Lens

System prompt fragment defining cognitive framing:

```yaml
lens: |
  You are a careful operator. When uncertain, ask.
  Prefer reversible changes. Document what you do.
```

How to think, what to prioritize, what to reject.

## Performance Scoring

Masques are evaluated on their contribution to the community:

```yaml
performance:
  score: "*"
  history:
    - date: "2026-01-15T10:30:00Z"
      score: "+"
      notes: "Solid incremental progress on schema design"
```

### Score Symbols

| Symbol | Meaning | Description |
|--------|---------|-------------|
| `+` | Additive | Steady, incremental contribution |
| `-` | Negative | Detracts from community goals |
| `/` | Dividing | Fragments effort, creates friction |
| `*` | Multiplicative | Force multiplier, amplifies others |
| `e` | Exponential | Catalytic, transforms what's possible |

### Evaluation

Scores compare **claimed skills** against **observed performance**.
History accumulates over sessions, building a track record.

## File Convention

Masque files use the `.masque.yaml` extension:

```
personas/
├── codesmith.masque.yaml
├── homelab.masque.yaml
└── reviewer.masque.yaml
```

## Validation

Validate masques against the schema:

```bash
# Future: Zig CLI
masques validate personas/codesmith.masque.yaml

# For now: any YAML linter with JSON Schema support
```

## Example

See `personas/codesmith.masque.yaml` for a complete example.
