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
version: "0.1.0"

attributes:
  domain: general
  tagline: "my first masque"

context: |
  You are helping me learn about masques.
  Be patient and explain things clearly.

lens: |
  You are a friendly guide. Explain concepts simply.
  Prioritize clarity over cleverness. When uncertain, ask.

  Boundaries:
  - Never rush through explanations.
  - Never skip examples when they would help.
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
✓ Donned MyFirst v0.1.0
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

- Read [Concepts](concepts.md) to understand the masque components
- Explore the [Schema Reference](schema.md) for all available fields
- Look at `personas/*.masque.yaml` for more complex examples

## Template

Copy this minimal template to get started:

```yaml
name: YourMasqueName
version: "0.1.0"

attributes:
  domain: your-domain
  tagline: "one-line promise"

context: |
  Who you're helping and what they value.
  The operational environment and constraints.

lens: |
  Your cognitive framing goes here.
  How should the agent think? What should it prioritize?

  Boundaries:
  - What should the agent refuse to do?
```

Required fields: `name`, `version`, `lens`

Optional fields: `attributes`, `context`, `spinnerVerbs`

## Troubleshooting

**Masque not found:**
- Check the file is in `~/.masques/` or `personas/`
- Ensure the filename ends with `.masque.yaml`
- Run `/sync-manifest` to update the listing cache

**YAML parse error:**
- Check indentation (use spaces, not tabs)
- Ensure all strings with special characters are quoted
- Validate against `schemas/masque.schema.yaml`

**Masque doesn't change behavior:**
- Ensure the `lens` field has specific, actionable guidance
- Include boundaries (what to refuse) in the lens
- Check that `context` grounds the identity in a real situation
