-- Migration: 20260312_sync_dashboard_metrics.sql
-- Ensure dashboard_performance_metrics stays in sync and provide backfill

-- 1) Create/replace trigger function (idempotent)
CREATE OR REPLACE FUNCTION public.update_dashboard_metrics()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
  v_period_id UUID;
  v_transaction_date DATE;
BEGIN
  IF TG_OP = 'DELETE' THEN
    v_user_id := OLD.promotor_id;
    v_transaction_date := OLD.transaction_date;
  ELSE
    v_user_id := NEW.promotor_id;
    v_transaction_date := NEW.transaction_date;
  END IF;

  SELECT tp.id INTO v_period_id
  FROM target_periods tp
  WHERE v_transaction_date BETWEEN tp.start_date AND tp.end_date
    AND tp.deleted_at IS NULL
  LIMIT 1;

  IF v_period_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  INSERT INTO dashboard_performance_metrics (
    user_id,
    period_id,
    total_omzet_real,
    total_units_focus,
    total_units_sold,
    estimated_bonus_total,
    last_updated
  )
  SELECT
    v_user_id,
    v_period_id,
    COALESCE(SUM(so.price_at_transaction), 0) AS total_omzet_real,
    COALESCE(COUNT(CASE WHEN p.is_focus = true OR p.is_fokus = true THEN 1 END), 0) AS total_units_focus,
    COALESCE(COUNT(*), 0) AS total_units_sold,
    COALESCE(SUM(so.estimated_bonus), 0) AS estimated_bonus_total,
    NOW()
  FROM sales_sell_out so
  JOIN product_variants pv ON so.variant_id = pv.id
  JOIN products p ON pv.product_id = p.id
  WHERE so.promotor_id = v_user_id
    AND so.transaction_date BETWEEN
      (SELECT start_date FROM target_periods WHERE id = v_period_id)
      AND
      (SELECT end_date FROM target_periods WHERE id = v_period_id)
    AND so.deleted_at IS NULL
  ON CONFLICT (user_id, period_id)
  DO UPDATE SET
    total_omzet_real = EXCLUDED.total_omzet_real,
    total_units_focus = EXCLUDED.total_units_focus,
    total_units_sold = EXCLUDED.total_units_sold,
    estimated_bonus_total = EXCLUDED.estimated_bonus_total,
    last_updated = NOW();

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- 2) Ensure trigger exists (insert/update/delete)
DROP TRIGGER IF EXISTS trg_update_dashboard_metrics ON public.sales_sell_out;
CREATE TRIGGER trg_update_dashboard_metrics
AFTER INSERT OR UPDATE OR DELETE ON public.sales_sell_out
FOR EACH ROW
EXECUTE FUNCTION public.update_dashboard_metrics();

-- 3) Backfill helper (optional)
CREATE OR REPLACE FUNCTION public.refresh_dashboard_performance_metrics(
  p_period_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF p_period_id IS NULL THEN
    -- rebuild all
    INSERT INTO dashboard_performance_metrics (
      user_id,
      period_id,
      total_omzet_real,
      total_units_focus,
      total_units_sold,
      estimated_bonus_total,
      last_updated
    )
    SELECT
      so.promotor_id,
      tp.id,
      COALESCE(SUM(so.price_at_transaction), 0) AS total_omzet_real,
      COALESCE(COUNT(CASE WHEN p.is_focus = true OR p.is_fokus = true THEN 1 END), 0) AS total_units_focus,
      COALESCE(COUNT(*), 0) AS total_units_sold,
      COALESCE(SUM(so.estimated_bonus), 0) AS estimated_bonus_total,
      NOW()
    FROM sales_sell_out so
    JOIN target_periods tp
      ON so.transaction_date BETWEEN tp.start_date AND tp.end_date
     AND tp.deleted_at IS NULL
    JOIN product_variants pv ON so.variant_id = pv.id
    JOIN products p ON pv.product_id = p.id
    WHERE so.deleted_at IS NULL
    GROUP BY so.promotor_id, tp.id
    ON CONFLICT (user_id, period_id)
    DO UPDATE SET
      total_omzet_real = EXCLUDED.total_omzet_real,
      total_units_focus = EXCLUDED.total_units_focus,
      total_units_sold = EXCLUDED.total_units_sold,
      estimated_bonus_total = EXCLUDED.estimated_bonus_total,
      last_updated = NOW();
  ELSE
    -- rebuild single period
    INSERT INTO dashboard_performance_metrics (
      user_id,
      period_id,
      total_omzet_real,
      total_units_focus,
      total_units_sold,
      estimated_bonus_total,
      last_updated
    )
    SELECT
      so.promotor_id,
      p_period_id,
      COALESCE(SUM(so.price_at_transaction), 0) AS total_omzet_real,
      COALESCE(COUNT(CASE WHEN p.is_focus = true OR p.is_fokus = true THEN 1 END), 0) AS total_units_focus,
      COALESCE(COUNT(*), 0) AS total_units_sold,
      COALESCE(SUM(so.estimated_bonus), 0) AS estimated_bonus_total,
      NOW()
    FROM sales_sell_out so
    JOIN target_periods tp
      ON tp.id = p_period_id
     AND so.transaction_date BETWEEN tp.start_date AND tp.end_date
    JOIN product_variants pv ON so.variant_id = pv.id
    JOIN products p ON pv.product_id = p.id
    WHERE so.deleted_at IS NULL
    GROUP BY so.promotor_id
    ON CONFLICT (user_id, period_id)
    DO UPDATE SET
      total_omzet_real = EXCLUDED.total_omzet_real,
      total_units_focus = EXCLUDED.total_units_focus,
      total_units_sold = EXCLUDED.total_units_sold,
      estimated_bonus_total = EXCLUDED.estimated_bonus_total,
      last_updated = NOW();
  END IF;
END;
$$;
