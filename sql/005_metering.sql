-- Masques Payment Infrastructure
-- 005: API Request Metering
--
-- Every 402-gated API request for usage analytics and billing.

CREATE TABLE IF NOT EXISTS masques.api_requests (
    request_id UUID,
    timestamp DateTime64(3),

    -- Identity
    identity_id UUID,
    session_id Nullable(UUID),  -- If within masque session

    -- Request details
    endpoint LowCardinality(String),  -- '/masque/pull', '/mcp/tool'
    method LowCardinality(String),

    -- Resource requested
    resource_type LowCardinality(String),
    resource_id String,

    -- Metering
    tokens_input UInt64 DEFAULT 0,
    tokens_output UInt64 DEFAULT 0,
    bytes_transferred UInt64 DEFAULT 0,
    duration_ms UInt32,

    -- Pricing
    price_usd Decimal64(6),  -- Price charged
    transaction_id Nullable(UUID),  -- Link to payment

    -- Outcome
    status_code UInt16,
    payment_status LowCardinality(String),  -- 'paid', 'free_tier', 'rejected', 'insufficient_funds'

    -- OTel
    trace_id String DEFAULT '',
    span_id String DEFAULT '',

    INDEX idx_identity identity_id TYPE bloom_filter GRANULARITY 1,
    INDEX idx_endpoint endpoint TYPE bloom_filter GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (timestamp, identity_id, request_id)
TTL toDateTime(timestamp) + INTERVAL 1 YEAR;
