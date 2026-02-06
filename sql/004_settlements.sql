-- Masques Payment Infrastructure
-- 004: Settlement Tables
--
-- Records of actual money movement to settlement rails (Lightning, Solana, etc.)

CREATE TABLE IF NOT EXISTS masques.settlements (
    settlement_id UUID,
    timestamp DateTime64(3),

    -- Settlement details
    rail LowCardinality(String),  -- 'lightning', 'solana', 'base'
    protocol LowCardinality(String),  -- 'l402', 'x402'

    -- Amount
    amount Decimal128(18),
    currency LowCardinality(String),  -- 'USD', 'BTC', 'SOL'

    -- Chain details
    tx_hash String DEFAULT '',  -- On-chain tx hash or Lightning payment hash
    block_height Nullable(UInt64),
    confirmations UInt32 DEFAULT 0,

    -- Parties
    from_account_id UUID,
    to_address String,  -- Lightning invoice, Solana address, etc.

    -- Status
    status LowCardinality(String),  -- 'pending', 'confirmed', 'failed'
    failure_reason String DEFAULT '',

    -- Fees
    network_fee Decimal128(18) DEFAULT 0,
    facilitator_fee Decimal128(18) DEFAULT 0,

    INDEX idx_tx tx_hash TYPE bloom_filter GRANULARITY 1,
    INDEX idx_account from_account_id TYPE bloom_filter GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (timestamp, settlement_id)
TTL toDateTime(timestamp) + INTERVAL 7 YEAR;
