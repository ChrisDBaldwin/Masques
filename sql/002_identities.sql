-- Masques Payment Infrastructure
-- 002: Identity Tables
--
-- Core identity records and masque session tracking.

-- Agent/user/service identities that interact with the system
CREATE TABLE IF NOT EXISTS masques.identities (
    identity_id UUID,
    identity_type LowCardinality(String),  -- 'agent', 'user', 'service'
    created_at DateTime64(3),

    -- Identity attributes (flexible)
    display_name String,
    attributes Map(LowCardinality(String), String),

    -- Linking (optional external identifiers)
    external_ids Map(LowCardinality(String), String),  -- 'did': 'did:key:...', 'lightning_node': '03abc...'

    -- Status
    status LowCardinality(String) DEFAULT 'active',  -- 'active', 'suspended', 'revoked'
    status_reason String DEFAULT '',
    updated_at DateTime64(3)
)
ENGINE = ReplacingMergeTree(updated_at)
ORDER BY (identity_id)
SETTINGS index_granularity = 8192;


-- Tracks when identities don/doff masques
CREATE TABLE IF NOT EXISTS masques.masque_sessions (
    session_id UUID,
    identity_id UUID,

    -- Masque info
    masque_name String,
    masque_version String,
    masque_source LowCardinality(String),  -- 'private', 'shared', 'marketplace'

    -- Timing
    donned_at DateTime64(3),
    doffed_at Nullable(DateTime64(3)),
    duration_ms Nullable(UInt64),

    -- Context
    intent String DEFAULT '',  -- User-provided intent when donning
    client_info Map(LowCardinality(String), String),  -- 'claude_code_version', 'os', etc.

    -- OTel correlation
    trace_id String DEFAULT '',

    INDEX idx_identity identity_id TYPE bloom_filter GRANULARITY 1,
    INDEX idx_masque masque_name TYPE bloom_filter GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(donned_at)
ORDER BY (donned_at, identity_id, session_id)
TTL toDateTime(donned_at) + INTERVAL 2 YEAR;
