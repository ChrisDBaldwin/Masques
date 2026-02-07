-- Masques Payment Infrastructure
-- 006: Reputation Tables
--
-- Raw reputation signals and aggregated scores.

-- Events that feed into reputation scoring
CREATE TABLE IF NOT EXISTS masques.reputation_events (
    event_id UUID,
    timestamp DateTime64(3),

    -- Subject
    identity_id UUID,

    -- Event classification
    category LowCardinality(String),  -- 'task_quality', 'economic', 'identity_hygiene'
    event_type LowCardinality(String),  -- 'task_completed', 'payment_failed', 'key_rotated'

    -- Score impact
    score_delta Float32,  -- Positive or negative impact
    confidence Float32 DEFAULT 1.0,  -- How confident in this signal

    -- Context
    reference_type LowCardinality(String) DEFAULT '',  -- 'session', 'transaction', 'attestation'
    reference_id String DEFAULT '',

    -- Details
    attributes Map(LowCardinality(String), String),

    INDEX idx_identity identity_id TYPE bloom_filter GRANULARITY 1,
    INDEX idx_category category TYPE bloom_filter GRANULARITY 1
)
ENGINE = MergeTree()
PARTITION BY toYYYYMM(timestamp)
ORDER BY (timestamp, identity_id, event_id)
TTL toDateTime(timestamp) + INTERVAL 3 YEAR;


-- Aggregated reputation scores per identity
CREATE TABLE IF NOT EXISTS masques.reputation_scores (
    identity_id UUID,
    computed_at DateTime64(3),

    -- Composite score
    overall_score Float32,

    -- Category scores
    task_quality_score Float32,
    economic_score Float32,
    identity_hygiene_score Float32,

    -- Stats
    total_events UInt64,
    positive_events UInt64,
    negative_events UInt64,

    -- Confidence
    confidence Float32,  -- Based on event count and recency

    -- History (for trend analysis)
    score_7d_ago Float32 DEFAULT 0,
    score_30d_ago Float32 DEFAULT 0
)
ENGINE = ReplacingMergeTree(computed_at)
ORDER BY (identity_id)
SETTINGS index_granularity = 8192;


-- Materialized view to auto-update reputation scores from events
CREATE MATERIALIZED VIEW IF NOT EXISTS masques.reputation_scores_mv
TO masques.reputation_scores
AS SELECT
    identity_id,
    now() as computed_at,
    -- Weighted composite (task quality 40%, economic 35%, identity hygiene 25%)
    (task_quality_score * 0.4 + economic_score * 0.35 + identity_hygiene_score * 0.25) as overall_score,
    task_quality_score,
    economic_score,
    identity_hygiene_score,
    total_events,
    positive_events,
    negative_events,
    least(1.0, total_events / 100.0) as confidence,
    0 as score_7d_ago,
    0 as score_30d_ago
FROM (
    SELECT
        identity_id,
        coalesce(sumIf(score_delta, category = 'task_quality') / nullIf(countIf(category = 'task_quality'), 0), 0) as task_quality_score,
        coalesce(sumIf(score_delta, category = 'economic') / nullIf(countIf(category = 'economic'), 0), 0) as economic_score,
        coalesce(sumIf(score_delta, category = 'identity_hygiene') / nullIf(countIf(category = 'identity_hygiene'), 0), 0) as identity_hygiene_score,
        count() as total_events,
        countIf(score_delta > 0) as positive_events,
        countIf(score_delta < 0) as negative_events
    FROM masques.reputation_events
    WHERE timestamp > now() - INTERVAL 90 DAY
    GROUP BY identity_id
);
