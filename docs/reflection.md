# Reflection Model

Masque uses a reflection model for observability — a layered system that lets masques see what they actually are through what they actually do. Actions aggregate upward; insights reflect back.

## The Five Levels

```
L5: System      ┌─────────────────────────────────┐
                │ Overall registry health         │
                │ Trending masques, skill gaps    │
                └─────────────────────────────────┘
                              │
                              │ aggregates
                              ▼
L4: Ring        ┌─────────────────────────────────┐
                │ Admin vs Player vs Guest        │
                │ Promotion/demotion signals      │
                └─────────────────────────────────┘
                              │
                              │ aggregates
                              ▼
L3: Skill       ┌─────────────────────────────────┐
                │ All masques claiming skill X    │
                │ Claimed level vs actual perf    │
                └─────────────────────────────────┘
                              │
                              │ aggregates
                              ▼
L2: Masque      ┌─────────────────────────────────┐
                │ Rating distribution over time   │
                │ Skill claims vs outcomes        │
                └─────────────────────────────────┘
                              │
                              │ aggregates
                              ▼
L1: Session     ┌─────────────────────────────────┐
                │ Single don/doff cycle           │
                │ Intent, duration, rating        │
                └─────────────────────────────────┘
```

## Self-Reflection

Without observability, masques are just costumes. With it, they become self-aware — personas that learn what they are from watching what they do.

The same question works at every level:

| Level | "How is X performing?" |
|-------|------------------------|
| Session | How did this one session go? |
| Masque | How is Codesmith performing over time? |
| Skill | How do Zig-skilled masques perform? |
| Ring | How is the Player tier performing? |
| System | How is the entire registry performing? |

The answer is always: **aggregate the ratings from the level below**.

## Query Pattern

```sql
-- The same pattern at every level, just change GROUP BY

-- L1: Session (no aggregation)
SELECT * FROM sessions WHERE id = ?;

-- L2: Masque
SELECT masque_name, count(*), avg(rating)
FROM sessions GROUP BY masque_name;

-- L3: Skill
SELECT skill_uri, claimed_level, avg(rating)
FROM sessions JOIN masque_skills ON ...
GROUP BY skill_uri, claimed_level;

-- L4: Ring
SELECT ring, count(*), avg(rating)
FROM sessions JOIN masques ON ...
GROUP BY ring;

-- L5: System
SELECT count(*), avg(rating) FROM sessions;
```

## Performance Scoring

Ratings use contribution symbols that capture *how* a masque affects the community:

| Symbol | Name | Numeric | Description |
|--------|------|---------|-------------|
| `+` | Additive | 1 | Steady, incremental contribution |
| `-` | Negative | -1 | Detracts from community goals |
| `/` | Dividing | 0 | Fragments effort, creates friction |
| `*` | Multiplicative | 2 | Force multiplier, amplifies others |
| `e` | Exponential | 3 | Catalytic, transforms what's possible |

## Data Flow

```
                    ┌──────────────┐
                    │  L5: System  │◄─── "How healthy is the registry?"
                    └──────┬───────┘
                           │
            ┌──────────────┼──────────────┐
            ▼              ▼              ▼
      ┌──────────┐   ┌──────────┐   ┌──────────┐
      │ L4: Ring │   │ L4: Ring │   │ L4: Ring │
      │  Admin   │   │  Player  │   │  Guest   │
      └────┬─────┘   └────┬─────┘   └────┬─────┘
           │              │              │
           ▼              ▼              ▼
      ┌─────────────────────────────────────────┐
      │              L3: Skills                 │
      │  zig, systems-design, pair-programming  │
      └───────────────────┬─────────────────────┘
                          │
           ┌──────────────┼──────────────┐
           ▼              ▼              ▼
      ┌──────────┐   ┌──────────┐   ┌──────────┐
      │L2:Masque │   │L2:Masque │   │L2:Masque │
      │Codesmith │   │ Homelab  │   │ Reviewer │
      └────┬─────┘   └────┬─────┘   └────┬─────┘
           │              │              │
           ▼              ▼              ▼
      ┌─────────────────────────────────────────┐
      │            L1: Sessions                 │
      │  The raw events. Every don/doff cycle.  │
      │  Source of truth for all reflections.   │
      └─────────────────────────────────────────┘
```

## Why Reflection?

1. **Self-awareness** — Masques learn what they are from observed behavior, not just claimed capabilities
2. **Accountability** — Claimed skill levels face the mirror of actual outcomes
3. **Drill-down** — System looks unhealthy? Check rings. Ring struggling? Check skills. Skill underperforming? Check masques. Masque off? Check sessions.
4. **Same tooling** — DuckDB + SQL works at every level, just change the GROUP BY

## Implementation

- **Entities** (JSON files): masques, skills — the definitions
- **Events** (Parquet): sessions, ratings — the observations
- **Query layer** (DuckDB): joins entities + events, aggregates at any level
- **CLI** (`masque stats`): surfaces the right level for the question
