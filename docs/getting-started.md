# Getting Started

Create your first masque in 5 minutes.

## Prerequisites

- Claude Code installed
- The masques plugin installed (via git clone or Claude Code plugin manager)

## Quick Start

### 1. Create a Private Masque

Create `~/.masques/my-first.masque.yaml`:

```yaml
name: MyFirst
index: 100
version: "0.1.0"
ring: player

attributes:
  domain: general
  tagline: "my first masque"

intent:
  allowed:
    - "help *"
    - "explain *"
  denied:
    - "rush *"

context: |
  You are helping me learn about masques.
  Be patient and explain things clearly.

lens: |
  You are a friendly guide. Explain concepts simply.
  When asked to do something outside your intent, politely decline
  and explain what you can help with instead.
```

### 2. Sync the Manifest

```
/sync-manifest private
```

This updates `~/.masques/manifest.yaml` so `/list` can find your masque.

### 3. Don Your Masque

```
/don myfirst
```

You should see:
```
✓ Donned MyFirst v0.1.0 (ring: player)
  my first masque
```

### 4. Verify It's Active

```
/id
```

Shows your current masque identity and when it was donned.

### 5. Doff When Done

```
/doff
```

Returns you to baseline Claude.

## Next Steps

- Read [Concepts](concepts.md) to understand the five components
- Explore the [Schema Reference](schema.md) for all available fields
- Look at `personas/*.masque.yaml` for more complex examples

## Template

Copy this minimal template to get started:

```yaml
name: YourMasqueName
index: 101  # Pick a unique number
version: "0.1.0"
ring: player

intent:
  allowed:
    - "your allowed patterns *"
  denied:
    - "patterns to deny *"

lens: |
  Your cognitive framing goes here.
  How should the agent think? What should it prioritize?
```

Required fields: `name`, `index`, `version`, `ring`, `intent`, `lens`

Optional fields: `attributes`, `context`, `knowledge`, `access`, `skills`, `mcp`

## Troubleshooting

**Masque not found:**
- Check the file is in `~/.masques/` or `personas/`
- Ensure the filename ends with `.masque.yaml`
- Run `/sync-manifest` to update the listing cache

**YAML parse error:**
- Check indentation (use spaces, not tabs)
- Ensure all strings with special characters are quoted
- Validate against `schemas/masque.schema.yaml`

**Intent patterns not matching:**
- Patterns use glob syntax (`*` matches anything)
- Both `allowed` and `denied` are checked; denied takes precedence
