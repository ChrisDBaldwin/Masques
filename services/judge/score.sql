-- score.sql — Two-layer scoring for one captured session (PRD D4).
--
-- Reads the `sessions` table (built by sessions.sql) and scores ONE target
-- session:
--
--   Layer A — the house reaction (always, from session one): a 7-point band
--     perfect · great · good · neutral · bad · awful · detracting.
--     Derived from observable activity signals (success, throughput, cost,
--     friction) — the honest home of the old five proxies. This answers
--     "how did this session go?", NEVER "did the masque cause it?".
--     If a rubric judge supplies a band (variable `rubric_band`), that band is
--     used instead and `judge: rubric`; otherwise `judge: activity-fallback`.
--
--   Layer B — lift (only when earned): the masque's mean vs the user's baseline
--     corpus for the SAME task_class. Shown only when the baseline cohort has
--     >= baseline_min sessions and the masque has >= 1 clean session of that
--     class. Below threshold, or for baseline/mixed sessions, Layer B is
--     suppressed (never a misleading number).
--
-- Inputs (set by judge.sh):
--   target_session — session.id to score (default: most recent by don_time)
--   rubric_band    — optional Layer-A band from an LLM/Witness judge (D7).
--                    Empty string => activity fallback.
--   baseline_min   — min baseline sessions per task_class before lift shows.
--
-- Output: YAML to stdout.

-- The supporting activity signals (DEMOTED from "the verdict" to context, D7).
-- These are the old proxies, reused honestly as Layer-A inputs.
WITH target AS (
  SELECT * FROM sessions
  WHERE session_id = NULLIF(getvariable('target_session'), '')
  UNION ALL
  SELECT * FROM sessions
  WHERE NULLIF(getvariable('target_session'), '') IS NULL
  ORDER BY don_time DESC
  LIMIT 1
),
sig AS (
  SELECT
    t.*,
    -- success rate 0-10
    ROUND((t.n_tools_ok::DOUBLE / GREATEST(t.n_tools, 1)) * 10, 2) AS s_success,
    -- throughput: tools_ok/min, 1/min => 10
    LEAST(10, ROUND((t.n_tools_ok::DOUBLE / GREATEST(t.duration_min, 1)) * 10, 2)) AS s_throughput,
    -- cost efficiency: $0 => 10, ~$0.10/tool => ~0
    LEAST(10, GREATEST(0, ROUND(10 - (t.cost_usd / GREATEST(t.n_tools_ok, 1)) * 100, 2))) AS s_cost,
    -- low friction: 1 - fail_rate, 0 fails => 10
    ROUND((1 - t.fail_rate) * 10, 2) AS s_friction
  FROM target t
),
activity AS (
  SELECT
    *,
    -- Layer-A activity composite (0-10). Weighted toward "did the work land and
    -- stick" (success + low friction) over raw speed. Tunable.
    ROUND(0.35*s_success + 0.20*s_throughput + 0.20*s_cost + 0.25*s_friction, 2) AS activity_score
  FROM sig
),
band AS (
  SELECT
    *,
    -- activity -> 7-point fallback band
    CASE
      WHEN activity_score >= 9.0 THEN 'perfect'
      WHEN activity_score >= 7.5 THEN 'great'
      WHEN activity_score >= 6.0 THEN 'good'
      WHEN activity_score >= 4.5 THEN 'neutral'
      WHEN activity_score >= 3.0 THEN 'bad'
      WHEN activity_score >= 1.5 THEN 'awful'
      ELSE 'detracting'
    END AS activity_band
  FROM activity
),
layerA AS (
  SELECT
    *,
    NULLIF(getvariable('rubric_band'), '') AS rubric_band_in,
    CASE WHEN NULLIF(getvariable('rubric_band'), '') IS NOT NULL
         THEN getvariable('rubric_band') ELSE activity_band END AS reaction,
    CASE WHEN NULLIF(getvariable('rubric_band'), '') IS NOT NULL
         THEN 'rubric' ELSE 'activity-fallback' END AS judge
  FROM band
),
-- Layer B: baseline + masque cohorts for the target's task_class.
cohorts AS (
  SELECT
    (SELECT task_class FROM layerA) AS tc,
    (SELECT masque     FROM layerA) AS mq,
    (SELECT attribution FROM layerA) AS attr_target,
    (SELECT COUNT(*) FROM sessions WHERE attribution='baseline'
        AND task_class=(SELECT task_class FROM layerA)) AS n_base,
    (SELECT AVG(fail_rate) FROM sessions WHERE attribution='baseline'
        AND task_class=(SELECT task_class FROM layerA)) AS base_fail,
    (SELECT COUNT(*) FROM sessions WHERE attribution='clean'
        AND masque=(SELECT masque FROM layerA)
        AND task_class=(SELECT task_class FROM layerA)) AS n_masque,
    (SELECT AVG(fail_rate) FROM sessions WHERE attribution='clean'
        AND masque=(SELECT masque FROM layerA)
        AND task_class=(SELECT task_class FROM layerA)) AS masque_fail
),
lift AS (
  SELECT
    *,
    -- lift is shown only when: target is a clean masque session, the baseline
    -- cohort is large enough, and the masque has >=1 clean session of this class.
    (attr_target = 'clean' AND mq IS NOT NULL
       AND n_base >= TRY_CAST(getvariable('baseline_min') AS BIGINT)
       AND n_masque >= 1) AS lift_ready,
    -- fewer failed tool calls is positive lift (PRD's worked example)
    CASE WHEN base_fail IS NOT NULL AND base_fail > 0
         THEN ROUND((base_fail - masque_fail) / base_fail * 100, 1) END AS lift_fail_pct
  FROM cohorts
)
SELECT printf(
'session: %s
masque: %s
attribution: %s
task_class: %s
duration_min: %.1f
layer_a:
  reaction: %s          # 7-point: perfect>great>good>neutral>bad>awful>detracting
  judge: %s
  activity_band: %s     # the activity-only fallback band (shown for transparency)
  activity_score: %.2f  # 0-10, supporting signal — NOT a masque verdict
layer_b:%s
supporting_signals:     # demoted proxies (D7) — context, never the verdict
  tool_success_pct: %.0f
  tools: %d
  tools_failed: %d
  throughput_per_min: %.2f
  cost_usd: %.2f
  cost_per_tool: %.4f
tool_mix: { read: %d, edit: %d, write: %d, bash: %d, search: %d, web: %d }',
  b.session_id,
  COALESCE(b.masque, 'null (baseline)'),
  b.attribution,
  b.task_class,
  b.duration_min,
  l_reaction.reaction, l_reaction.judge, b.activity_band, b.activity_score,
  -- Layer B block: either a real lift line, or an honest "not yet" note.
  CASE WHEN lift.lift_ready AND lift.lift_fail_pct IS NOT NULL THEN
    printf('
  status: shown
  vs: your baseline corpus (same task_class)
  failed_tool_calls_lift_pct: %+.1f   # positive = fewer failures than baseline
  baseline_sessions: %d
  masque_sessions: %d', lift.lift_fail_pct, lift.n_base, lift.n_masque)
  WHEN b.attribution = 'baseline' THEN '
  status: n/a (this IS a baseline session — nothing to lift against)'
  WHEN b.attribution = 'mixed' THEN '
  status: excluded (mixed attribution — multiple masques this session, PRD D2)'
  ELSE printf('
  status: not_yet
  reason: baseline corpus too thin for task_class "%s"
  baseline_sessions: %d / %s needed', b.task_class, lift.n_base, getvariable('baseline_min'))
  END,
  b.n_tools_ok::DOUBLE / GREATEST(b.n_tools,1) * 100,
  b.n_tools, b.n_tools_fail,
  b.s_throughput,
  b.cost_usd,
  b.cost_usd / GREATEST(b.n_tools_ok,1),
  b.n_read, b.n_edit, b.n_write, b.n_bash, b.n_search, b.n_web
) AS yaml_output
FROM band b, layerA l_reaction, lift
WHERE b.session_id = l_reaction.session_id;
