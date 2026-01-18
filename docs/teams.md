# Multi-Agent Teams

A single agent with a masque is useful. Multiple agents with complementary masques form a **team**. This is where masques shine.

## The MMORPG Pattern

The pattern mirrors MMORPGs, where success requires complementary roles:

| MMORPG | Software Team | Function |
|--------|---------------|----------|
| Tank | Orchestrator | Absorbs complexity, directs flow |
| Healer | QA / Reviewer | Catches damage, ensures health |
| DPS | Engineer | Does the work, ships output |

No single role succeeds alone. The tank can't kill the boss. The healer can't deal damage. The DPS dies without protection. Success requires composition.

## Why This Analogy?

Traditional software teams already work this way:

| Role | Focus | Masque Pattern |
|------|-------|----------------|
| Engineer | Builds, codes, implements | High access, focused intent |
| PM | Prioritizes, clarifies, decides scope | Broad context, limited access |
| Architect | Designs, reviews, ensures coherence | Deep knowledge, review-focused intent |
| QA | Tests, catches issues, validates | Read access, validation intent |

Masques make these roles explicit and composable. The personas aren't just individuals—they're **positions in a formation**.

## Team Composition

```bash
# Spawn a team with complementary masques
claude team spawn \
  --masque engineer:backend@v1 \
  --masque engineer:frontend@v1 \
  --masque reviewer@v2 \
  --intent "implement user authentication feature"
```

Each agent:
- Has its own masque (identity, access, lens)
- Shares a common intent (the team goal)
- Can communicate with teammates
- Cannot assume another's masque

## Formation Examples

### Feature Development

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Engineer   │────▶│  Reviewer   │────▶│     PM      │
│  (builds)   │     │ (validates) │     │  (accepts)  │
└─────────────┘     └─────────────┘     └─────────────┘
```

### Investigation

```
┌─────────────┐     ┌─────────────┐
│   Analyst   │────▶│  Reporter   │
│(investigates)     │ (documents) │
└─────────────┘     └─────────────┘
```

### Operations

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Operator   │◀───▶│   Monitor   │◀───▶│  On-call    │
│  (changes)  │     │ (observes)  │     │ (escalates) │
└─────────────┘     └─────────────┘     └─────────────┘
```

## Conflict Resolution

When agents with different masques disagree, the system doesn't auto-resolve. Conflict resolution is organic:

### 1. Discourse First

Use words to reach consensus. Agents with different lenses see problems differently—that's the point. They should articulate their perspectives and find common ground.

### 2. Escalate If Stuck

If discourse fails, raise to outside actors:
- Humans (the ultimate arbiter)
- Other systems (automated policy evaluation)
- Higher-ring agents (if one exists)

The system surfaces conflicts rather than hiding them.

## Team Boundaries

### Shared

- **Intent**: All agents serve the same goal
- **Context**: All agents understand the situation
- **Communication**: Agents can message each other

### Not Shared

- **Access**: Each agent has its own credentials
- **Knowledge**: Each agent queries its own sources
- **Lens**: Each agent thinks its own way

This separation is intentional. A reviewer shouldn't have write access just because the engineer does. Different roles, different capabilities.

## Inheritance Rules

When an agent in a team spawns a sub-agent:

1. Sub-agent does NOT inherit the parent's masque
2. Sub-agent does NOT automatically join the team
3. Sub-agent must explicitly assume a masque
4. Sub-agent must explicitly join the team (if allowed)

No accidental privilege escalation through team membership.

## Team Lifecycle

### Formation

1. Declare team intent
2. Assign masques to positions
3. Each agent assumes its masque
4. Work begins

### Operation

1. Agents work within their masques
2. Communication happens through defined channels
3. Conflicts surface and resolve
4. Progress toward shared intent

### Dissolution

1. Intent is achieved (or abandoned)
2. Each agent doffs its masque
3. Session credentials expire
4. Work product persists, team does not
