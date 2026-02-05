# Concepts

This document explains the components of a masque—not just what they are, but why they exist and how they form a coherent system.

## What is a Masque?

A masque answers one question: **"Who am I right now, and why?"**

Traditional identity systems answer pieces of this:
- Personas answer "how should I behave?" (prompts)
- Config answers "where are my resources?" (endpoints)

But these are fragments. A complete identity needs:

1. **Lens** — How to think and what to avoid
2. **Context** — Who you're helping and what situation you're in
3. **Attributes** — Metadata that describes this identity

## The Components

### Lens — The Framing

**How to think, not just what to do.**

The lens is cognitive framing—priorities, heuristics, things to prefer or avoid. It shapes *how* the agent approaches problems.

```yaml
lens: |
  You are a careful operator. When uncertain, ask.
  Prefer reversible changes. Document what you do.
  Stability over novelty. Boring is good.

  Boundaries:
  - Never delete production data without approval.
  - Never rush deployments.
```

The lens includes intent guidance as prose—what to do and what to avoid. This reads naturally and keeps everything about "how to behave" in one place.

### Context — The Situation

**Every masque operates in a situation.**

Context grounds the abstract identity in reality. Who are you helping? What do they value? What's the domain? This isn't just metadata—it's cognitive framing that shapes judgment.

```yaml
context: |
  Building infrastructure for a small homelab.
  The human prioritizes stability over novelty.
  Budget is constrained; prefer open source.
```

### Attributes — The Metadata

**Flexible key-value pairs.**

Attributes describe the masque without affecting behavior directly. They're useful for display, filtering, and organization.

```yaml
attributes:
  domain: database-architecture
  tagline: "graceful growth, efficient queries"
  style: opinionated-collaborative
```

## How They Relate

The components form a simple hierarchy:

```
        ┌─────────────────┐
        │   ATTRIBUTES    │
        │   (metadata)    │
        └────────┬────────┘
                 │ describes
                 ▼
        ┌─────────────────┐
        │    CONTEXT      │
        │  (situation)    │
        └────────┬────────┘
                 │ grounds
                 ▼
        ┌─────────────────┐
        │      LENS       │
        │   (framing)     │
        └─────────────────┘
```

**Attributes describe** what this masque is about.

**Context grounds** the masque in a specific situation.

**Lens shapes** how the agent thinks and works.

## Session Lifecycle

A masque has three phases:

### Don

The agent assumes the masque. This:
1. Injects context and lens
2. Updates session state
3. Applies spinner verbs (if defined)

### Work

The agent operates with full identity context. Every action is:
- Informed by context
- Shaped by lens

### Doff

The session ends. This:
1. Clears session state
2. Restores default behavior

## Versioning

Masque definitions must be versioned. Auto-updating is dangerous—a changed masque mid-session could alter behavior unexpectedly.

```bash
/don homelab "deploying monitoring"
```

Changes require conscious adoption. You pin to a version. Upgrading is a deliberate act.

## What Masques Doesn't Do

Masques is intentionally limited. It provides identity, not infrastructure:

| Need | Not Masques' Job |
|------|------------------|
| Knowledge lookup | Use MCP servers (Context7, etc.) |
| Credentials | Use vault/credential managers |
| Tool bundles | Use Claude Code MCP config |
| Performance tracking | Use observability tools (OTEL) |

This keeps masques simple: **who you are**, not **what you can do**.
