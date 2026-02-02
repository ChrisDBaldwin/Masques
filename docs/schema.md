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

spinnerVerbs:       # Optional. Custom spinner display
  mode: replace     # replace|append|prepend
  verbs:
    - "Masque:Verb..."

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
  credentials:
    - source: aws-secrets-manager
      scope: read-only
  capabilities:
    database: read
    writes: file-output-only

lens: |             # Required. Cognitive framing
  System prompt fragment.

mcp:                # Optional. Bundled MCP servers
  servers:
    - name: server-name
      type: stdio
      command: npx
      args: ["-y", "@package/name"]

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

Determines who can assume this masque.

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

> **Ecosystem Integration:** Skill declarations integrate with external skill systems (like Claude Code skills). The masque claims a proficiency level; the skill system can adjust behavior accordingly. For example, a masque claiming "expert" in a skill might receive less guidance than one claiming "novice."

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

> **Ecosystem Integration:** Knowledge URIs are declarative — they document where knowledge *would* come from when MCP servers are available. The masque declares relevance; the ecosystem provides content. This allows masques to work today (prompting user for context) while evolving to full automation as infrastructure matures.

### 4. Access

Credential and capability configuration:

```yaml
access:
  vault_role: homelab-operator
  ttl: session
  credentials:
    - source: aws-secrets-manager
      scope: read-only
  capabilities:
    database: read
    writes: file-output-only
```

#### Properties

| Property | Description |
|----------|-------------|
| `vault_role` | Role to assume for credential minting |
| `ttl` | `session` (expires when masque is doffed) or ISO 8601 duration |
| `credentials` | Array of credential sources |
| `capabilities` | Object defining granted capabilities |

#### Credentials

Each credential entry specifies:
- `source`: Where credentials come from (e.g., `aws-secrets-manager`, `vault`)
- `scope`: Access level (e.g., `read-only`, `read-write`)

#### Capabilities

Freeform object declaring what the masque can do. Common patterns:
- `database: read` — read-only database access
- `writes: file-output-only` — can only write to files, not execute
- `logs: [ecs, ec2]` — access to specific log sources

> **Ecosystem Integration:** Access declarations are currently declarative — they document what credentials *would* be needed when vault/credential infrastructure exists. The masque declares needs; vault/credential tools fulfill them. Until that infrastructure is deployed, the agent should request credentials directly from the user.

### 5. Lens

System prompt fragment defining cognitive framing:

```yaml
lens: |
  You are a careful operator. When uncertain, ask.
  Prefer reversible changes. Document what you do.
```

How to think, what to prioritize, what to reject.

## MCP Server Bundling

Masques can bundle MCP servers to provide domain-specific tools:

```yaml
mcp:
  servers:
    - name: zig-docs
      type: stdio
      command: npx
      args: ["-y", "@anthropic/mcp-zig-docs"]
    - name: local-tools
      type: stdio
      command: python
      args: ["./servers/tools.py"]
      env:
        API_KEY: "${API_KEY}"
```

### Server Properties

| Property | Required | Description |
|----------|----------|-------------|
| `name` | Yes | Unique identifier for the server |
| `type` | Yes | Transport type: `stdio`, `sse`, or `http` |
| `command` | Yes | Command to start the server |
| `args` | No | Array of command arguments |
| `env` | No | Environment variables for the server |

### On Don

When a masque with MCP servers is donned, the plugin displays instructions for enabling the servers:

```
This masque bundles MCP servers:
• zig-docs: npx -y @anthropic/mcp-zig-docs

To enable: claude mcp add zig-docs -- npx -y @anthropic/mcp-zig-docs
```

> **Ecosystem Integration:** MCP server declarations are suggestions for the Claude Code MCP configuration. The masque suggests what servers would be useful; Claude Code's MCP system handles the actual server lifecycle. This keeps masques declarative while leveraging the ecosystem for execution.

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

> **Ecosystem Integration:** Performance scoring provides context for external evaluation systems. The masque tracks self-assessment; evaluation frameworks can use this data for calibration and trust decisions. The history field enables longitudinal analysis across sessions.

## File Convention

Masque files use the `.masque.yaml` extension:

```
personas/
├── codesmith.masque.yaml
├── homelab.masque.yaml
└── reviewer.masque.yaml
```

## Validation

Validate masques against the schema using any YAML linter with JSON Schema support.

The formal schema is at `schemas/masque.schema.yaml`.

## Example

See `personas/codesmith.masque.yaml` for a complete example.
