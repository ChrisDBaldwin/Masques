# Masques Payment Infrastructure - ClickHouse Schema

Database schema for the Masques payment infrastructure, supporting identity management, financial ledger (TigerBeetle sync), settlement rails, and reputation scoring.

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   MCP Request   │───▶│  402 Payment     │───▶│   TigerBeetle   │
│   (masque pull) │    │  Gate (x402/L402)│    │   (ledger)      │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │                        │
                              ▼                        ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │   Settlement     │    │   ClickHouse    │
                       │ (Lightning/Sol)  │    │   (analytics)   │
                       └──────────────────┘    └─────────────────┘
```

## Tables

| Table | Purpose | Engine |
|-------|---------|--------|
| `identities` | Agent/user/service identity records | ReplacingMergeTree |
| `masque_sessions` | Masque don/doff tracking | MergeTree |
| `accounts` | TigerBeetle balance snapshots | ReplacingMergeTree |
| `transactions` | Payment event log | MergeTree |
| `settlements` | On-chain/Lightning settlements | MergeTree |
| `api_requests` | 402-gated request metering | MergeTree |
| `reputation_events` | Raw reputation signals | MergeTree |
| `reputation_scores` | Aggregated scores (+ MV) | ReplacingMergeTree |

## Running Migrations

Execute SQL files in order against your ClickHouse instance:

```bash
# Using clickhouse-client
for f in sql/0*.sql; do
  clickhouse-client --multiquery < "$f"
done

# Or individually
clickhouse-client --multiquery < sql/001_create_database.sql
clickhouse-client --multiquery < sql/002_identities.sql
clickhouse-client --multiquery < sql/003_ledger.sql
clickhouse-client --multiquery < sql/004_settlements.sql
clickhouse-client --multiquery < sql/005_metering.sql
clickhouse-client --multiquery < sql/006_reputation.sql
```

## Verification

After running migrations, verify tables exist:

```sql
SELECT name, engine FROM system.tables WHERE database = 'masques';
```

Expected output:
```
┌─name───────────────────┬─engine──────────────┐
│ accounts               │ ReplacingMergeTree  │
│ api_requests           │ MergeTree           │
│ identities             │ ReplacingMergeTree  │
│ masque_sessions        │ MergeTree           │
│ reputation_events      │ MergeTree           │
│ reputation_scores      │ ReplacingMergeTree  │
│ reputation_scores_mv   │ MaterializedView    │
│ settlements            │ MergeTree           │
│ transactions           │ MergeTree           │
└────────────────────────┴─────────────────────┘
```

## Integration Points

### TigerBeetle Sync
- Periodic job syncs `accounts` snapshots
- Transaction stream writes to `transactions`
- Use TigerBeetle's `id` as `account_id`/`transaction_id`

### OTel Correlation
- `trace_id` and `span_id` fields link to existing `otel.otel_traces`
- Enables joining payment data with request traces

### x402/L402 Protocol
- `settlements` table records on-chain settlement
- `api_requests.payment_status` tracks 402 flow

## Data Retention (TTL)

| Table | Retention |
|-------|-----------|
| `masque_sessions` | 2 years |
| `transactions` | 7 years |
| `settlements` | 7 years |
| `api_requests` | 1 year |
| `reputation_events` | 3 years |
| `identities`, `accounts`, `reputation_scores` | No TTL (active records) |
