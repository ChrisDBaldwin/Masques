# The Vision: Theater for Machines

> "All the world's a stage, and all the men and women merely players."
> — Shakespeare, *As You Like It*

The theater has solved coordination problems for millennia. Actors don costumes and personas, perform within defined roles, and return to themselves when the curtain falls. Directors orchestrate ensembles. Stage managers coordinate logistics. The production succeeds not because individuals are controlled, but because roles are clear.

Masque brings this model to autonomous agents.

## The Insight

Human organizations already work like theater companies. We have roles (engineer, reviewer, on-call), contexts (this sprint, this incident, this customer), and boundaries (what I'm responsible for, what I escalate). When contexts shift, we mentally "change hats."

Agents need the same primitive.

Not permissions alone—*identity*. Not configuration—*role*. Not instructions—*intent*.

## The Five Components

A masque bundles everything an agent needs to become someone:

```
                    ┌─────────────────────────────────────┐
                    │             M A S Q U E             │
                    └─────────────────────────────────────┘
                                      │
        ┌─────────────┬───────────────┼───────────────┬─────────────┐
        │             │               │               │             │
        ▼             ▼               ▼               ▼             ▼
   ┌─────────┐  ┌─────────┐    ┌───────────┐   ┌─────────┐   ┌─────────┐
   │ INTENT  │  │ CONTEXT │    │ KNOWLEDGE │   │ ACCESS  │   │  LENS   │
   │         │  │         │    │           │   │         │   │         │
   │ The Why │  │ The Who │    │ The What  │   │ The How │   │  Frame  │
   └─────────┘  └─────────┘    └───────────┘   └─────────┘   └─────────┘
        │             │               │               │             │
        │             │               │               │             │
        ▼             ▼               ▼               ▼             ▼
    ┌───────────────────────────────────────────────────────────────────┐
    │                        COHERENT IDENTITY                          │
    │                                                                   │
    │   "I am Codesmith. I build foundational systems with clarity.    │
    │    I know where to look things up. I have the credentials I      │
    │    need. I understand what I'm allowed to do—and refuse to       │
    │    cut corners."                                                  │
    │                                                                   │
    └───────────────────────────────────────────────────────────────────┘
```

**Intent** drives everything. Without stated goals, you're just collecting access. The intent says what you're *trying to accomplish*—and what you refuse to do.

**Context** grounds it. Every masque operates in a situation: a project, a user, a set of values to respect.

**Knowledge** enables it. Masques point to MCP servers for lookups. Knowledge stays fresh at the source instead of going stale in embeddings.

**Access** permits it. Credentials scoped to the task, minted for the session, expired when done. No persistent keys lying around.

**Lens** shapes approach. How to think about problems. What to prioritize. What heuristics to apply. The cognitive style.

## The Theater Model

Think of agents like actors in a production:

| Theater | Masque |
|---------|--------|
| Actor | Agent |
| Role/Character | Masque |
| Costume & Props | Access & Knowledge |
| Script & Direction | Intent & Lens |
| Scene | Session |
| Backstage | Base agent (no masque) |

When an actor enters a scene, they *become* the character. They have the character's knowledge, motivations, and manner of speaking. When the scene ends, they step backstage and return to themselves.

Agents work the same way:

```bash
/don codesmith "implementing the parser"    # Enter character
# ... work happens with full identity ...
/doff                                       # Exit to backstage
```

## Why This Matters

### The Configuration Problem

Today's agents get configured through scattered mechanisms:

- System prompts (persona)
- MCP servers (capabilities)
- Environment variables (credentials)
- Knowledge bases (context)
- Tool permissions (access)

These are disconnected. Switching contexts means manually reconfiguring multiple systems. There's no unified "become this identity" operation.

### The Identity Solution

Masque unifies configuration into a single primitive. Donning a masque sets up *everything*:

```
┌──────────────────────────────────────────────────────────────┐
│                     WITHOUT MASQUE                           │
│                                                              │
│   Agent ──┬── reads system prompt                           │
│           ├── connects to MCP servers                        │
│           ├── loads environment variables                    │
│           ├── configures knowledge base                      │
│           └── ... hope they're all consistent ...            │
│                                                              │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│                      WITH MASQUE                             │
│                                                              │
│   Agent ── dons masque ── becomes coherent identity          │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

### Continuous Qualification

Traditional permissions ask: "Do you have access?"

Trust rings ask: "Do you *still* qualify?"

This matters for long-running agents. Circumstances change. What was appropriate at session start may not be appropriate now. Trust rings continuously evaluate qualification instead of granting permanent access.

```
           ADMIN ─────────────────────────────────────────► Full access
              │   (still on the team? still on this project?)
              ▼
           PLAYER ────────────────────────────────────────► Normal work
              │   (still working on declared intent?)
              ▼
           GUEST ─────────────────────────────────────────► Read mostly
              │   (still need to be here at all?)
              ▼
          OUTSIDER ───────────────────────────────────────► Nothing
```

### Graceful Revocation

When sessions end—or trust is revoked—agents don't crash. They wind down with dignity:

1. Current work completes or checkpoints
2. Credentials are revoked
3. Work product is preserved
4. Session context is archived

Like an actor finishing a scene rather than being dragged off stage.

## The Ensemble

Agents don't work alone. Masque supports multi-agent coordination:

```
                    ┌───────────────────┐
                    │      ENSEMBLE     │
                    │                   │
                    │   shared context  │
                    │   conflict rules  │
                    │   communication   │
                    └───────────────────┘
                            │
         ┌──────────────────┼──────────────────┐
         │                  │                  │
         ▼                  ▼                  ▼
   ┌───────────┐      ┌───────────┐      ┌───────────┐
   │ ARCHITECT │      │ CODESMITH │      │ REVIEWER  │
   │           │      │           │      │           │
   │  designs  │ ───► │  builds   │ ───► │ validates │
   └───────────┘      └───────────┘      └───────────┘
```

Each masque has its role. Conflicts resolve through defined protocols. The ensemble produces coherent work even when individual agents have different perspectives.

## Looking Forward

Masque starts simple: one agent, one masque, one session.

But the model scales:

- **Teams** of agents with complementary masques
- **Nested sessions** where agents delegate work
- **Mesh networks** where peers discover each other
- **Versioned identities** that upgrade deliberately

The foundation is the same: temporary, coherent, intentional identity.

---

*See [Concepts](concepts.md) for component details and [Schema](schema.md) for the full YAML specification.*
