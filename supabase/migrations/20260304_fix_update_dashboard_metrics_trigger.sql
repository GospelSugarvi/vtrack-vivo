-- Fix typo in dashboard metrics trigger function:
-- products.is_fokus -> products.is_focus

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
    last_updated
  )
  SELECT
    v_user_id,
    v_period_id,
    COALESCE(SUM(so.price_at_transaction), 0) AS total_omzet_real,
    COALESCE(COUNT(CASE WHEN p.is_focus = true THEN 1 END), 0) AS total_units_focus,
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
    last_updated = NOW();

  RETURN COALESCE(NEW, OLD);
END;
$$;
