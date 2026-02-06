# Session Prompt: TigerBeetle Integration for Masque Payments

## Context

Masques is an agent identity framework — "AssumeRole for Agents." Agents don masques (temporary cognitive identities) created by masque authors. **Masque authors get paid when their masques are used.** A popular masque used by many agents many times a day represents real income for its creator.

The repo is at `~/git/masques` on branch `feat/payment-clickhouse-schema`.

### What exists today

- **ClickHouse schema** on ironwood (`sql/001-006`): identity tables, ledger tables (TigerBeetle mirrors), settlements, API request metering, reputation scoring. See `sql/README.md` for the full architecture diagram.
- **OTEL collector** running locally, shipping metrics and logs to ironwood's ClickHouse (`otel` database). Config in `services/collector/`. Uses `.env` for connection details (gitignored).
- **Masque plugin** for Claude Code: `/don`, `/doff`, `/id`, `/list` commands. Session state in `.claude/masque.session.yaml`.
- **No traces/spans yet** — Claude Code only emits metrics and logs. We're building on that intentionally to document the gaps for an OTEL span classification proposal (see `docs/span-classification-spec.md`).

### What needs to be built

TigerBeetle is the source of truth for all money movement. ClickHouse gets analytical copies for dashboards and metering queries. The flow:

```
Agent dons masque
  → masque_sessions record created
  → TigerBeetle: create pending transfer (debit agent's account, credit masque author's account)

Agent works with masque (tools, tokens consumed)
  → metrics/logs flow to ClickHouse via OTEL collector
  → api_requests table tracks usage

Agent doffs masque (or session ends)
  → TigerBeetle: post the transfer (finalize based on actual usage)
  → ClickHouse: transactions table gets analytical copy
  → Masque author's balance increases

Author requests settlement
  → TigerBeetle: debit author's account
  → Settlement rail (Lightning/Solana/Base) moves real money
  → ClickHouse: settlements table records it
```

### Key design decisions to make

1. **Account structure** — What TigerBeetle accounts does each identity get? Prepaid (agent loads balance first) vs postpaid (metered, settled later)? Escrow accounts for pending sessions?

2. **Transfer lifecycle** — TigerBeetle supports two-phase transfers (pending → posted/voided). A masque session maps naturally to this: pending on don, posted on doff. But what if a session crashes without doffing? Timeout policy?

3. **Pricing model** — Flat per-session fee? Per-token? Per-minute? Per-tool-call? The ClickHouse metering tables can calculate any of these, but the TigerBeetle transfer amount needs to be determined somehow.

4. **Integration point** — Where does TigerBeetle run? On ironwood alongside ClickHouse? Locally? The masque plugin needs to communicate with it on don/doff events. Direct client? Via an API service?

5. **Sync to ClickHouse** — Periodic snapshots of TigerBeetle account balances → `masques.accounts` table. Transaction stream → `masques.transactions` table. What frequency? Event-driven or polling?

### Resources

- TigerBeetle docs: https://docs.tigerbeetle.com
- ClickHouse schema: `sql/` directory in the repo
- Masque session state: `.claude/masque.session.yaml`
- Collector config: `services/collector/config.yaml`
- Span classification spec: `docs/span-classification-spec.md`
- Beads issue tracker: `bd show masques-2e9` (OTEL→ClickHouse task, in progress)

### Constraints

- This is an open source repo. No hardcoded hostnames, credentials, or personal infrastructure references in committed files. Use `.env` patterns with `.env.example` templates.
- Build for logs/metrics first (what Claude Code emits today). Document where traces/spans would improve the system — these gaps feed the OTEL proposal.
- TigerBeetle is the ledger of record. ClickHouse is analytics. Never reverse this — ClickHouse reads from TigerBeetle, not the other way around.
