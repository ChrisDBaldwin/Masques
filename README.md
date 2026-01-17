# Masque

**AssumeRole for Agents.** A masque is a temporary cognitive identity an agent can don — bundling context, knowledge, access, and lens into a single assumable primitive.

## The Problem

Agents today get configured through scattered mechanisms:
- System prompts (persona)
- MCP servers (capabilities)
- Environment variables (credentials)
- Knowledge bases (context)

These are disconnected. Switching contexts means manually reconfiguring multiple systems. There's no unified "become this identity" operation.

## The Primitive

A masque bundles five things:

| Component | What it provides |
|-----------|------------------|
| **Intent** | Why are you wearing this? Toward what goal? |
| **Context** | Who am I helping? What do they value? What's the domain? |
| **Knowledge** | Pointers to information sources. Lookups, not blobs. |
| **Access** | Credentials, endpoints, APIs. The keys, scoped appropriately. |
| **Lens** | How to approach problems. What to prioritize. What to reject. |

Intent is first-class. Without stated intent, you're just collecting access. The masque is in service of something larger — the greater goal ahead.

When you assume a masque, you get all five. When the session ends, the masque is doffed — credentials expire, but work product remains.

## IAM Mapping

The semantics mirror AWS AssumeRole:

| IAM AssumeRole | Masque |
|----------------|--------|
| Role ARN | Masque identifier |
| Trust policy | Who can don this masque (rings) |
| Permission policy | What access it grants |
| Session token | The active masque session |
| Session duration | How long before it expires |
| Role session name | Intent — why it was assumed |

But extended beyond permissions to include knowledge, cognitive lens, and stated intent.

## Trust Rings

Not everyone can assume every masque. Trust rings determine who can don what:

| Ring | Description | Can Assume |
|------|-------------|------------|
| **Admin** | Full trust. The operator. | Any masque |
| **Player** | Trusted participant. Has skin in the game. | Most masques, with audit |
| **Guest** | Temporary access. Supervised. | Limited masques, scoped sessions |
| **Outsider** | No trust. Public interface only. | Public masques only |

**Rings represent current qualification, not static membership.**

Traditional IAM asks "do you have permission?" Rings ask "do you *still* qualify?" The masque is stable — it defines what the role requires, grants, and expects. But whether an entity can don it is evaluated continuously.

### Continual Approval

Qualification isn't a self-check. It requires ongoing non-disapproval from higher rings. Teachers know students; students see peers and maybe the teacher's friends. The hierarchy is visible downward, opaque upward.

### Tournament Merit

Promotion happens through demonstrated competence under environmental circumstance. You don't apply for a ring — you earn it through action. Hierarchy is ephemeral, constantly challenged, as it should be.

### No Ring Skipping

You cannot skip rings unless you're founding the community. Founders start at the center. Everyone else climbs. The center is principled elders who care about the world, not the clan's survival for its own sake. (See Charles Vogl's work on community.)

See [rings/README.md](rings/README.md) for the full model.

## Knowledge Architecture

Knowledge is **pointers, not blobs**. A masque doesn't contain knowledge — it points to knowledge sources via thin MCP servers that vend lookups.

```
masque:homelab
  └── knowledge:
        - mcp://homelab-inventory    # what machines exist
        - mcp://homelab-history      # what's been done
        - mcp://homelab-runbooks     # how to do things
```

This keeps masques lightweight and knowledge fresh. The MCP servers are the source of truth; the masque just knows where to look.

## Versioning

Masque definitions must be versioned. Auto-updating is dangerous — a changed masque mid-session could grant unexpected access or revoke needed capabilities.

```
claude assume masque:homelab@v2.3 --intent "deploying monitoring"
```

Changes require conscious adoption. You pin to a version. Upgrading is a deliberate act.

## Revocation

Revocation must be graceful. Not a hard yank — the session should wind down with dignity. The agent should be notified, given a chance to checkpoint work, and released cleanly.

Ungraceful revocation is for emergencies only.

## Multi-Agent Teams

This is where masques shine.

A single agent with a masque is useful. Multiple agents with complementary masques form a **team**. The pattern mirrors MMORPGs:

| MMORPG | Software Team | Function |
|--------|---------------|----------|
| Tank | Orchestrator | Absorbs complexity, directs flow |
| Healer | QA / Reviewer | Catches damage, ensures health |
| DPS | Engineer | Does the work, ships output |

Or product teams:
- **Engineer masque** — builds, codes, implements
- **PM masque** — prioritizes, clarifies, decides scope
- **Architect masque** — designs, reviews, ensures coherence

Masques let you compose teams with defined roles. The personas aren't just individuals — they're **positions in a formation**.

## Usage

```
# Assume a masque with stated intent
claude assume masque:homelab@v2.3 --intent "deploying monitoring stack"

# Agent now has: intent, credentials, knowledge pointers, operational lens

# Work happens...

# Session ends, masque doffed automatically
```

For teams:
```
# Spawn a team with complementary masques
claude team spawn \
  --masque engineer:backend@v1 \
  --masque engineer:frontend@v1 \
  --masque reviewer@v2 \
  --intent "implement user authentication feature"
```

## Directory Structure

```
masque/
├── README.md                       # This file
├── docs/
│   ├── schema.md                   # Schema reference guide
│   └── reflection.md               # Reflection model for observability
├── schemas/
│   └── masque.schema.yaml          # Formal JSON Schema for masques
├── personas/                       # Masque definitions
│   └── codesmith.masque.yaml       # Example: methodical systems builder
├── rings/
│   └── README.md                   # Full trust ring model
├── src/                            # Zig implementation (in progress)
│   ├── main.zig
│   └── root.zig
└── build.zig                       # Zig build system
```

## Design Principles

1. **Intent-driven** — Every assumption has a stated goal.
2. **Session-scoped** — Masques are temporary. Don, work, doff.
3. **Bundled** — Intent, context, knowledge, access, lens travel together.
4. **Pointer-based** — Knowledge is looked up, not contained.
5. **Versioned** — Pin to versions. Upgrade deliberately.
6. **Auditable** — Every assumption logged with intent.
7. **Composable** — Masques can form teams.
8. **Graceful** — Revocation with dignity.

## Session Boundaries

Sessions operate at two levels:

- **Global**: Agent session lifetime — the masque is worn for the entire conversation/instance
- **Local**: Per-prompt scoping — temporary elevation or restriction for a specific operation

This allows for both persistent identity and momentary adjustments.

## Sub-Agent Inheritance

Sub-agents **do not inherit masques by default**. When an agent spawns a sub-agent, the child starts fresh. No accidental masque leakage. If the sub-agent needs a masque, it must explicitly assume one (and qualify for it).

## Conflict Resolution

When agents with different masques disagree:

1. **Discourse first** — Use words to reach consensus
2. **Escalate if stuck** — Raise to outside actors: humans, or other systems

This is organic, not algorithmic. The system doesn't auto-resolve conflicts; it surfaces them.

## Masques as Programs

Masques should not be documentation (`.md` files). They should be **the smallest programs that efficiently power the system**.

A masque is executable code that produces:
- Intent validation
- Context injection
- Knowledge pointers (MCP URIs)
- Access tokens (minted or fetched)
- Lens (system prompt fragment)

Could be full code:
```python
# masque/homelab.py
class Homelab(Masque):
    version = "2.3"
    ring_required = Ring.PLAYER

    def validate_intent(self, intent: str) -> bool:
        ...

    def knowledge(self) -> list[str]:
        return ["mcp://homelab-inventory", "mcp://homelab-runbooks"]

    def access(self, session: Session) -> Credentials:
        return vault.mint_temporary("homelab-operator", ttl=session.duration)

    def lens(self) -> str:
        return """You're operating Chris's homelab..."""
```

Or a declarative DSL that compiles to runnable code:
```yaml
# masque/homelab.masque
version: 2.3
ring: player

intent:
  allowed_patterns: ["deploy *", "debug *", "investigate *"]
  denied_patterns: ["delete *", "destroy *"]

knowledge:
  - mcp://homelab-inventory
  - mcp://homelab-runbooks

access:
  vault_role: homelab-operator
  ttl: session

lens: |
  You're operating Chris's homelab...
```

The current format is `.masque.yaml` — a declarative DSL. See [docs/schema.md](docs/schema.md) for the specification.

## Reflection Model

Masques are self-aware through observability. Actions aggregate upward; insights reflect back across five levels:

| Level | Question Answered |
|-------|-------------------|
| Session | How did this one session go? |
| Masque | How is Codesmith performing over time? |
| Skill | How do Zig-skilled masques perform? |
| Ring | How is the Player tier performing? |
| System | How is the entire registry performing? |

Each level aggregates from the one below. DuckDB + SQL provides the query layer.

See [docs/reflection.md](docs/reflection.md) for the full model.

## Performance Scoring

Masques are rated on their contribution to the community using contribution symbols:

| Symbol | Name | Description |
|--------|------|-------------|
| `+` | Additive | Steady, incremental contribution |
| `-` | Negative | Detracts from community goals |
| `/` | Dividing | Fragments effort, creates friction |
| `*` | Multiplicative | Force multiplier, amplifies others |
| `e` | Exponential | Catalytic, transforms what's possible |

Scores compare **claimed skills** against **observed performance**.

## Schema

Masques are defined in `.masque.yaml` files. See [docs/schema.md](docs/schema.md) for the full reference or [schemas/masque.schema.yaml](schemas/masque.schema.yaml) for the formal JSON Schema.

Quick example:

```yaml
name: Codesmith
index: 1
version: "0.1.0"
ring: player

skills:
  - uri: skill://programming/zig
    level: competent

intent:
  allowed: ["implement *", "test *"]
  denied: ["rush *"]

lens: |
  You are a methodical builder...
```

## Status

Design documentation complete. Zig implementation in progress.
