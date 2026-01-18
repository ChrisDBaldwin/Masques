# Concepts

This document explains the five components of a masque—not just what they are, but why these five and how they form a coherent system.

## Why Five Components?

A masque answers one question: **"Who am I right now, and why?"**

Traditional identity systems answer pieces of this:
- IAM answers "what can I do?" (permissions)
- Personas answer "how should I behave?" (prompts)
- Config answers "where are my resources?" (endpoints)

But these are fragments. A complete identity needs all five:

### Intent — The Why

**Without intent, you're just collecting access.**

Intent is first-class because it constrains everything else. A masque isn't just capabilities—it's capabilities *in service of something*. The intent declaration:

- States what goals this assumption serves
- Defines allowed/denied action patterns
- Provides audit trail for "why was this assumed?"

```yaml
intent:
  allowed: ["deploy *", "debug *"]
  denied: ["delete production *"]
```

### Context — The Who

**Every masque operates in a situation.**

Context grounds the abstract identity in reality. Who are you helping? What do they value? What's the domain? This isn't just metadata—it's cognitive framing that shapes judgment.

```yaml
context: |
  Building infrastructure for a small homelab.
  The human prioritizes stability over novelty.
  Budget is constrained; prefer open source.
```

### Knowledge — The What

**Pointers, not blobs.**

Masques don't contain knowledge—they know where to look. This keeps masques lightweight and knowledge fresh. MCP servers are the source of truth; the masque just holds URIs.

```yaml
knowledge:
  - mcp://homelab-inventory    # what machines exist
  - mcp://homelab-runbooks     # how to do things
  - mcp://homelab-history      # what's been done
```

### Access — The How

**Credentials scoped to the task.**

Access isn't just "what APIs can I call"—it's credentials minted for this specific session, scoped to what the intent requires, expired when done.

```yaml
access:
  vault_role: homelab-operator
  ttl: session  # expires when masque is doffed
```

### Lens — The Framing

**How to think, not just what to do.**

The lens is cognitive framing—priorities, heuristics, things to prefer or avoid. It shapes *how* the agent approaches problems, not just what it can access.

```yaml
lens: |
  You are a careful operator. When uncertain, ask.
  Prefer reversible changes. Document what you do.
  Stability over novelty. Boring is good.
```

## How They Relate

The five components aren't a checklist—they're a system:

```
                    ┌─────────────────┐
                    │     INTENT      │
                    │   (the why)     │
                    └────────┬────────┘
                             │ constrains
        ┌────────────────────┼────────────────────┐
        │                    │                    │
        ▼                    ▼                    ▼
   ┌─────────┐         ┌──────────┐         ┌─────────┐
   │ CONTEXT │         │ KNOWLEDGE│         │  ACCESS │
   │(the who)│         │(the what)│         │(the how)│
   └────┬────┘         └────┬─────┘         └────┬────┘
        │                   │                    │
        └───────────────────┼────────────────────┘
                            │ shapes
                            ▼
                    ┌─────────────────┐
                    │      LENS       │
                    │ (the framing)   │
                    └─────────────────┘
```

**Intent sits at the top** because it constrains what's appropriate. You can't use knowledge or access that doesn't serve the intent.

**Context, Knowledge, and Access are peers** that provide the raw materials. They're what you have available.

**Lens synthesizes below** because it determines *how* you use what you have. It's shaped by everything above it.

## Session Lifecycle

A masque has three phases:

### Don

The agent assumes the masque. This:
1. Validates the agent qualifies (trust ring check)
2. Validates the stated intent matches allowed patterns
3. Mints session credentials
4. Injects context and lens
5. Registers knowledge sources

### Work

The agent operates with full identity context. Every action is:
- Constrained by intent
- Informed by context and knowledge
- Enabled by access
- Shaped by lens

### Doff

The session ends. This:
1. Expires session credentials
2. Logs session for reflection
3. Preserves work product
4. Releases masque for future assumption

**Credentials expire, but work product remains.**

## Session Boundaries

Sessions operate at two levels:

- **Global**: The masque is worn for the entire conversation/instance
- **Local**: Temporary elevation or restriction for a specific operation

This allows both persistent identity and momentary adjustments. A homelab operator might temporarily elevate to admin for a specific dangerous operation, then drop back.

## Sub-Agent Inheritance

**Sub-agents do not inherit masques by default.**

When an agent spawns a sub-agent, the child starts fresh. No accidental masque leakage. If the sub-agent needs a masque, it must explicitly assume one—and qualify for it.

This is a security feature. Masques are explicit, not ambient. You don't inherit someone else's identity just because they called you.

## Versioning

Masque definitions must be versioned. Auto-updating is dangerous—a changed masque mid-session could grant unexpected access or revoke needed capabilities.

```bash
claude assume masque:homelab@v2.3 --intent "deploying monitoring"
```

Changes require conscious adoption. You pin to a version. Upgrading is a deliberate act.

## Revocation

Revocation must be graceful. Not a hard yank—the session should wind down with dignity:

1. Agent is notified
2. Given chance to checkpoint work
3. Released cleanly

Ungraceful revocation is for emergencies only.
