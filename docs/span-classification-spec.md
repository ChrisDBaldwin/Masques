# OTEL Spans Need Public/Private Classification

> Status: Draft proposal for OpenTelemetry semantic convention
> Date: 2026-02-05

## Summary

OpenTelemetry spans should support a `public` boolean attribute that indicates whether a span's data is safe to export beyond the originating system. Without this, agent-to-agent observability systems are forced to either expose everything or observe nothing.

## Motivation

We're building Masques, an identity framework for AI agents. When an agent dons a masque (a temporary cognitive identity), we need to:

1. Track that the masque was used (for paying the masque creator)
2. Meter the usage (tokens, duration, tool calls)
3. Correlate usage with the agent's identity
4. **Not** leak the agent's prompts, reasoning, or code to the masque creator or any other observer

OTEL's current model gives us metrics (counters, gauges) and logs (events). We're building on those today. But here's what we can't do:

### What logs/metrics give us

- A masque was donned at time T, doffed at time T+N
- During that window, X tool calls happened, Y tokens were consumed
- The session produced Z metrics data points

### What logs/metrics can't give us

- **Causal relationships** — which tool calls were *caused by* the masque's lens vs the user's intent? Logs are flat events. There's no parent-child relationship.
- **Scoped metering** — if an agent dons masque A, calls a tool, then dons masque B and calls another tool, logs can't cleanly attribute which call belongs to which masque session without fragile timestamp correlation.
- **Trust-bounded context** — a masque creator should see that their masque was used for 45 minutes and consumed 12k tokens. They should *not* see what the agent was building. Logs don't have a built-in way to say "this field is for the creator" vs "this field is for the agent owner."

Traces solve the structural problem — spans have parent-child relationships, scoped attributes, and clear boundaries. But traces don't solve the trust problem. Every attribute on a span is equally visible to every consumer of that trace.

## Proposal

Add a single boolean attribute to the OTEL semantic conventions:

```
otel.public: true | false
```

- `true` — this span and its attributes may be exported to external observers, aggregated across trust boundaries, and used for billing/metering.
- `false` — this span stays within the originating system's trust boundary. External observers see that a span *exists* (for structural completeness) but not its attributes.

### Why boolean

- One bit. Cheapest possible metadata overhead.
- No ambiguity. No "who decides what tier 2 means."
- Easy to enforce at the collector level: filter attributes where `otel.public = false` before exporting.
- Composable with existing OTEL access control — this doesn't replace auth, it augments it.

## Evidence We're Building

Masques is being built on logs and metrics specifically to document the gaps. We expect to demonstrate:

1. **Attribution breaks at masque boundaries** — when an agent switches masques mid-session, log-based correlation produces incorrect metering.
2. **Flat events lose causality** — without span hierarchy, we can't distinguish "tool call triggered by masque lens" from "tool call triggered by user override."
3. **All-or-nothing visibility blocks adoption** — masque creators won't publish to a marketplace if it means their users' work is visible. Users won't use marketplace masques if it means the creator sees their code.

Each of these failures will be documented with concrete data from the running system.

## For the OTEL Community

This isn't a masques-specific need. Any system where:

- Multiple agents or services observe each other's work
- Billing requires usage attribution across trust boundaries
- IP or PII exists in span attributes alongside operational metrics

...will hit the same wall. The agent ecosystem is growing fast. The sooner spans have a trust classification, the less fragile workaround code gets written.
