-- Masques Payment Infrastructure
-- 003: Ledger Tables
--
-- TigerBeetle account mirrors and transaction logs for analytics.
-- TigerBeetle remains the source of truth; these are analytical copies.

-- Periodic snapshots from TigerBeetle for analytics
CREATE TABLE IF NOT EXISTS masques.accounts (
    account_id UUID,  -- Matches TigerBeetle account ID
    identity_id UUID,

    -- Balance snapshot
    snapshot_at DateTime64(3),
    credits_posted Decimal128(18),
    debits_posted Decimal128(18),
    credits_pending Decimal128(18),
    debits_pending Decimal128(18),

    balance Decimal128(18) MATERIALIZED credits_posted - debits_posted,

    -- Account metadata
    currency LowCardinality(String) DEFAULT 'USD',
    account_type LowCardinality(String),  -- 'prepaid', 'postpaid', 'escrow'

    INDEX idx_identity identity_id TYPE bloom_filter GRANULARITY 1
)
ENGINE = ReplacingMergeTree(snapshot_at)
ORDER BY (account_id)
SETTINGS index_granularity = 8192;


-- Immutable log of all payment events (synced from TigerBeetle)
CREATE TABLE IF NOT EXISTS masques.transactions (
    transaction_id UUID,
    timestamp DateTime64(3),

    -- Parties
    debit_account_id UUID,
    credit_account_id UUID,

    -- Amount
    amount Decimal128(18),
    currency LowCardinality(String) DEFAULT 'USD',

    -- Classification
    transaction_type LowCardinality(String),  -- 'api_call', 'settlement', 'refund', 'fee'

    -- Reference to what was paid for
    resource_type LowCardinality(String),  -- 'masque', 'mcp_tool', 'storage', 'compute'
    resource_id String DEFAULT '',

    -- State (two-phase from TigerBeetle)
    status LowCardinality(String),  -- 'pending', 'posted', 'voided'

    -- Metadata
    attributes Map(LowCardinality(String), String),

    -- OTel correlation
    trace_id String DEFAULT '',
    span_id String DEFAULT '',

    INDEX idx_debit debit_account_id TYPE bloom_filter GRANULARITY 1,
    INDEX idx_credit credit_account_id TYPE bloom_filter GRANULARITY 1,
    INDEX idx_resource (resource_type, resource_id) TYPE bloom_filter GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (timestamp, transaction_id)
TTL toDateTime(timestamp) + INTERVAL 7 YEAR;
