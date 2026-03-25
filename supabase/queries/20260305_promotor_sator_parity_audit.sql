-- PROMOTOR vs SATOR parity audit
-- Run in Supabase SQL Editor
-- 1) Replace v_sator_id below
-- 2) Optional: change v_audit_date

WITH cfg AS (
  SELECT
    '00000000-0000-0000-0000-000000000000'::uuid AS v_sator_id,
    CURRENT_DATE::date AS v_audit_date
),
period AS (
  SELECT
    v_sator_id,
    v_audit_date,
    date_trunc('month', v_audit_date)::date AS month_start,
    (date_trunc('month', v_audit_date) + interval '1 month')::date AS month_end
  FROM cfg
),
team_promotors AS (
  SELECT DISTINCT hsp.promotor_id
  FROM hierarchy_sator_promotor hsp
  JOIN period p ON p.v_sator_id = hsp.sator_id
  WHERE hsp.active = true
  UNION
  SELECT DISTINCT aps.promotor_id
  FROM assignments_sator_store ass
  JOIN assignments_promotor_store aps
    ON aps.store_id = ass.store_id
   AND aps.active = true
  JOIN period p ON p.v_sator_id = ass.sator_id
  WHERE ass.active = true
),
sales_day AS (
  SELECT s.*
  FROM sales_sell_out s
  JOIN period p ON s.transaction_date = p.v_audit_date
  WHERE s.deleted_at IS NULL
    AND s.promotor_id IN (SELECT promotor_id FROM team_promotors)
),
sales_month AS (
  SELECT s.*
  FROM sales_sell_out s
  JOIN period p
    ON s.transaction_date >= p.month_start
   AND s.transaction_date < p.month_end
  WHERE s.deleted_at IS NULL
    AND s.promotor_id IN (SELECT promotor_id FROM team_promotors)
),
rpc_live_all AS (
  SELECT *
  FROM get_live_feed(
    (SELECT v_sator_id FROM period),
    (SELECT v_audit_date FROM period),
    500,
    0
  )
),
rpc_live_team AS (
  SELECT *
  FROM rpc_live_all
  WHERE promotor_id IN (SELECT promotor_id FROM team_promotors)
),
rpc_team_leaderboard_raw AS (
  SELECT get_team_leaderboard(
    (SELECT v_sator_id FROM period),
    to_char((SELECT v_audit_date FROM period), 'YYYY-MM')
  )::jsonb AS data
),
rpc_team_leaderboard AS (
  SELECT
    (elem->>'promotor_id')::uuid AS promotor_id,
    COALESCE((elem->>'total_units')::int, 0) AS total_units,
    COALESCE((elem->>'total_revenue')::numeric, 0) AS total_revenue,
    COALESCE((elem->>'total_bonus')::numeric, 0) AS total_bonus
  FROM rpc_team_leaderboard_raw r,
  LATERAL jsonb_array_elements(r.data) elem
)
SELECT
  check_name,
  expected_value,
  actual_value,
  CASE WHEN expected_value = actual_value THEN 'PASS' ELSE 'FAIL' END AS status
FROM (
  SELECT
    'TEAM_SIZE'::text AS check_name,
    (SELECT count(*)::text FROM team_promotors) AS expected_value,
    (SELECT count(*)::text FROM team_promotors) AS actual_value

  UNION ALL

  SELECT
    'LIVE_FEED_ROWS_DAY (table vs get_live_feed+team-filter)'::text,
    (SELECT count(*)::text FROM sales_day),
    (SELECT count(*)::text FROM rpc_live_team)

  UNION ALL

  SELECT
    'LIVE_FEED_WITH_IMAGE (table vs get_live_feed+team-filter)'::text,
    (SELECT count(*)::text FROM sales_day WHERE image_proof_url IS NOT NULL AND image_proof_url <> ''),
    (SELECT count(*)::text FROM rpc_live_team WHERE image_url IS NOT NULL AND image_url <> '')

  UNION ALL

  SELECT
    'MONTH_TOTAL_UNITS (table vs get_team_leaderboard)'::text,
    (SELECT count(*)::text FROM sales_month),
    (SELECT COALESCE(sum(total_units), 0)::text FROM rpc_team_leaderboard)

  UNION ALL

  SELECT
    'MONTH_TOTAL_REVENUE (table vs get_team_leaderboard)'::text,
    (SELECT COALESCE(sum(price_at_transaction), 0)::text FROM sales_month),
    (SELECT COALESCE(sum(total_revenue), 0)::text FROM rpc_team_leaderboard)

  UNION ALL

  SELECT
    'MONTH_TOTAL_BONUS (table vs get_team_leaderboard)'::text,
    (SELECT COALESCE(sum(estimated_bonus), 0)::text FROM sales_month),
    (SELECT COALESCE(sum(total_bonus), 0)::text FROM rpc_team_leaderboard)
) q
ORDER BY check_name;

-- Detail mismatch helper: rows from table missing in RPC live feed
WITH cfg AS (
  SELECT
    '00000000-0000-0000-0000-000000000000'::uuid AS v_sator_id,
    CURRENT_DATE::date AS v_audit_date
),
team_promotors AS (
  SELECT DISTINCT hsp.promotor_id
  FROM hierarchy_sator_promotor hsp
  JOIN cfg c ON c.v_sator_id = hsp.sator_id
  WHERE hsp.active = true
),
sales_day AS (
  SELECT s.id, s.promotor_id, s.image_proof_url, s.created_at
  FROM sales_sell_out s
  JOIN cfg c ON s.transaction_date = c.v_audit_date
  WHERE s.deleted_at IS NULL
    AND s.promotor_id IN (SELECT promotor_id FROM team_promotors)
),
rpc_live_team AS (
  SELECT sale_id
  FROM get_live_feed(
    (SELECT v_sator_id FROM cfg),
    (SELECT v_audit_date FROM cfg),
    500,
    0
  )
  WHERE promotor_id IN (SELECT promotor_id FROM team_promotors)
)
SELECT
  s.id AS missing_sale_id,
  s.promotor_id,
  s.image_proof_url,
  s.created_at
FROM sales_day s
LEFT JOIN rpc_live_team r ON r.sale_id = s.id
WHERE r.sale_id IS NULL
ORDER BY s.created_at DESC
LIMIT 50;
