# Future / Deferred

This directory holds the **deferred vision** for masques — work that is intentionally *not* part of the current minimal product.

Masques today is a representation tool: a masque bundles a cognitive identity (lens + context + attributes) that you can don on top of any agent, optionally measured via OTEL telemetry. That's the whole product.

The documents here describe where masques could grow once that core is solid — an **agent marketplace** where masques are spawned as first-class workers and authors get paid for usage:

- **`roadmap.md`** — the agent-factory pivot: an MCP server that spawns a fresh agent process with the masque baked in as a turn-0 system prompt, with a reputation + payment gate before spawn.
- **`tigerbeetle-integration.md`** — the payment-rail design: TigerBeetle as the ledger of record, two-phase transfers (escrow on don, settle on doff), author payouts.

None of this is wired into the shipping plugin. The payment/reputation ClickHouse schema (formerly `sql/`) was removed for the minimal product. These docs are preserved so the vending-machine direction is a deliberate decision away — not lost.
