# Trust Rings

Trust rings determine who can assume which masques. But unlike traditional access control, rings represent *current qualification*, not static membership.

## The Core Insight

**The masque is stable. The entity assuming it is not.**

Traditional IAM operates on "once trusted, trusted until revoked." Communities know better: trust decays, incentives drift, people change. Someone who was once great for a community can become harmful when their incentives shift.

Masques don't change. They're the definition of what a role requires, what it grants, what it expects. But whether an entity can don a masque is evaluated *continuously*. You were a great admin once? Doesn't matter. Your incentives shifted. You don't qualify anymore. No masque.

This is the corruption problem solved: someone who *has* a role but *shouldn't* is a failure of continuous qualification. Rings aren't about what you were granted — they're about what you currently qualify for.

## Communities as Graphs

Communities are graphs with opaque connections. Some edges are clear, some hidden. Some nodes are large and important, others peripheral. The structure is tree-like but messier — the environment in which the community exists shapes what's possible.

Communities are vulnerable to:
- **Privilege escalation through impersonation** — pretending to be something you're not
- **Trust decay** — someone who once qualified no longer does
- **Misaligned incentives** — the community's structure rewards the wrong behavior
- **Corruption** — an admin who shouldn't be anywhere near power

These are graph problems. IAM is a graph system. The mathematical webbing is the same — roles, trust relationships, policy evaluation. But traditional IAM ignores the temporal dimension. It asks "do you have permission?"

Rings ask: **"do you still qualify?"**

## The Four Rings

Rings represent current relationship to the system, not historical grants.

### Admin
*Full trust. The operator.*

**Qualification**: Currently aligned with system goals. Currently competent. Currently accountable. Has skin in the game at the highest level.

**Can assume**: Any masque. Full access to all personas, including dangerous ones.

**Risk**: Corruption. An admin with misaligned incentives is the worst failure mode. Continuous qualification is most critical here.

---

### Player
*Trusted participant. Has skin in the game.*

**Qualification**: Currently invested in outcomes. Currently contributing value. Currently honest in dealings. Incentives are aligned with the community.

**Can assume**: Most masques, with audit trail. Operational access to systems they work with.

**Risk**: Incentive drift. A player who stops contributing or whose goals diverge. The community changes, or they do.

---

### Guest
*Temporary access. Supervised.*

**Qualification**: Currently supervised by a higher ring. Currently scoped to specific tasks. Explicitly temporary — there's an end condition.

**Can assume**: Limited masques with hard boundaries. Scoped sessions that expire.

**Risk**: Scope creep. Guests becoming de facto players without proper qualification. The temporary becoming permanent.

---

### Outsider
*No trust. Public interface only.*

**Qualification**: None required. This is the default state. No relationship, no trust, no access beyond what's public.

**Can assume**: Public masques only — personas designed for zero-trust interaction.

**Risk**: Impersonation. An outsider pretending to be a higher ring. The system must verify qualification, not assume it.

---

## For Agents

This matters even more for agents than humans. Agents don't have persistent identity the way humans do. Each session is a fresh evaluation. The agent must prove it qualifies each time it dons a masque.

This is a feature, not a bug. Humans accumulate trust (and corruption) over time. Agents start fresh. The masque is the constant; qualification is proven, not assumed.

```
# Every assumption is an evaluation
claude assume masque:homelab --reason "deploying monitoring"

# The system asks: does this agent, in this context,
# with this reason, currently qualify for this masque?
```

## Qualification Signals

How do you know if someone still qualifies? Some signals:

- **Recency of contribution** — are they still active?
- **Alignment of actions** — do recent actions match stated goals?
- **Accountability** — do they accept consequences of their access?
- **Vouching** — do other qualified members still vouch for them?
- **Behavior patterns** — does their usage match expected patterns?

For agents, qualification might include:
- **Session context** — what triggered this assumption?
- **Request patterns** — is this a reasonable ask?
- **Audit history** — how have previous assumptions gone?
- **Explicit authorization** — did a higher ring approve this?

## The Temporal Dimension

AWS asks: "Do you have permission?"
Rings ask: "Do you *still* qualify?"

The masque is stable. The entity is not. Qualification is continuous.
