-- Unify promotor bonus RPCs to a single transaction-based source with
-- ledger fallback to sales_sell_out.estimated_bonus.

CREATE OR REPLACE FUNCTION public.get_promotor_bonus_summary_from_events(
  p_promotor_id UUID,
  p_start_date DATE DEFAULT NULL,
  p_end_date DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start_date DATE;
  v_end_date DATE;
  v_result JSON;
BEGIN
  v_start_date := COALESCE(p_start_date, DATE_TRUNC('month', CURRENT_DATE)::DATE);
  v_end_date := COALESCE(
    p_end_date,
    (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE
  );

  WITH sale_bonus AS (
    SELECT
      sso.id AS sales_sell_out_id,
      sso.promotor_id,
      sso.transaction_date,
      sso.price_at_transaction,
      CASE
        WHEN COALESCE(SUM(sbe.bonus_amount), 0) > 0 THEN COALESCE(SUM(sbe.bonus_amount), 0)::NUMERIC
        WHEN COALESCE(sso.estimated_bonus, 0) > 0 THEN COALESCE(sso.estimated_bonus, 0)::NUMERIC
        ELSE 0::NUMERIC
      END AS total_bonus,
      CASE
        WHEN COALESCE(SUM(sbe.bonus_amount), 0) > 0 THEN COALESCE(
          MAX(sbe.bonus_type) FILTER (WHERE COALESCE(sbe.bonus_amount, 0) > 0),
          'range'
        )
        WHEN COALESCE(sso.estimated_bonus, 0) > 0 THEN 'range'
        ELSE COALESCE(MAX(sbe.bonus_type), 'excluded')
      END AS effective_bonus_type
    FROM public.sales_sell_out sso
    LEFT JOIN public.sales_bonus_events sbe ON sbe.sales_sell_out_id = sso.id
    WHERE sso.promotor_id = p_promotor_id
      AND sso.transaction_date BETWEEN v_start_date AND v_end_date
      AND sso.deleted_at IS NULL
      AND COALESCE(sso.is_chip_sale, false) = false
    GROUP BY sso.id, sso.promotor_id, sso.transaction_date, sso.price_at_transaction, sso.estimated_bonus
  ),
  grouped_bonus AS (
    SELECT
      sb.effective_bonus_type AS bonus_type_key,
      SUM(sb.total_bonus)::NUMERIC AS bonus_total
    FROM sale_bonus sb
    GROUP BY sb.effective_bonus_type
  )
  SELECT json_build_object(
    'promotor_id', p_promotor_id,
    'period_start', v_start_date,
    'period_end', v_end_date,
    'event_count', COALESCE((SELECT COUNT(*) FROM sale_bonus), 0),
    'total_sales', COALESCE((SELECT COUNT(*) FROM sale_bonus), 0),
    'total_revenue', COALESCE((SELECT SUM(price_at_transaction) FROM sale_bonus), 0),
    'total_bonus', COALESCE((SELECT SUM(total_bonus) FROM sale_bonus), 0),
    'by_bonus_type', COALESCE(
      (SELECT jsonb_object_agg(gb.bonus_type_key, gb.bonus_total) FROM grouped_bonus gb),
      '{}'::jsonb
    )
  )
  INTO v_result;

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_promotor_bonus_details_from_events(
  p_promotor_id UUID,
  p_start_date DATE DEFAULT NULL,
  p_end_date DATE DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  bonus_event_id UUID,
  sales_sell_out_id UUID,
  transaction_date DATE,
  serial_imei TEXT,
  price_at_transaction NUMERIC,
  bonus_type TEXT,
  bonus_amount NUMERIC,
  is_projection BOOLEAN,
  calculation_version TEXT,
  notes TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_start_date DATE;
  v_end_date DATE;
BEGIN
  v_start_date := COALESCE(p_start_date, DATE_TRUNC('month', CURRENT_DATE)::DATE);
  v_end_date := COALESCE(
    p_end_date,
    (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month - 1 day')::DATE
  );

  RETURN QUERY
  WITH sale_bonus AS (
    SELECT
      sso.id AS sales_sell_out_id,
      sso.transaction_date,
      sso.serial_imei,
      sso.price_at_transaction,
      CASE
        WHEN COALESCE(SUM(sbe.bonus_amount), 0) > 0 THEN COALESCE(SUM(sbe.bonus_amount), 0)::NUMERIC
        WHEN COALESCE(sso.estimated_bonus, 0) > 0 THEN COALESCE(sso.estimated_bonus, 0)::NUMERIC
        ELSE 0::NUMERIC
      END AS total_bonus,
      CASE
        WHEN COALESCE(SUM(sbe.bonus_amount), 0) > 0 THEN COALESCE(
          MAX(sbe.bonus_type) FILTER (WHERE COALESCE(sbe.bonus_amount, 0) > 0),
          'range'
        )
        WHEN COALESCE(sso.estimated_bonus, 0) > 0 THEN 'range'
        ELSE COALESCE(MAX(sbe.bonus_type), 'excluded')
      END AS effective_bonus_type,
      COALESCE(BOOL_OR(sbe.is_projection), TRUE) AS effective_is_projection,
      COALESCE(MAX(sbe.calculation_version), 'estimated_bonus_fallback_v1') AS effective_calculation_version,
      COALESCE(
        MAX(sbe.notes) FILTER (WHERE COALESCE(sbe.bonus_amount, 0) > 0),
        CASE
          WHEN COALESCE(sso.estimated_bonus, 0) > 0 THEN 'Derived from sales_sell_out.estimated_bonus'
          ELSE MAX(sbe.notes)
        END
      ) AS effective_notes
    FROM public.sales_sell_out sso
    LEFT JOIN public.sales_bonus_events sbe ON sbe.sales_sell_out_id = sso.id
    WHERE sso.promotor_id = p_promotor_id
      AND sso.transaction_date BETWEEN v_start_date AND v_end_date
      AND sso.deleted_at IS NULL
      AND COALESCE(sso.is_chip_sale, false) = false
    GROUP BY sso.id, sso.transaction_date, sso.serial_imei, sso.price_at_transaction, sso.estimated_bonus
  )
  SELECT
    sb.sales_sell_out_id AS bonus_event_id,
    sb.sales_sell_out_id,
    sb.transaction_date,
    sb.serial_imei,
    sb.price_at_transaction,
    sb.effective_bonus_type,
    sb.total_bonus,
    sb.effective_is_projection,
    sb.effective_calculation_version,
    sb.effective_notes
  FROM sale_bonus sb
  ORDER BY sb.transaction_date DESC, sb.sales_sell_out_id DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_promotor_bonus_summary(
  p_promotor_id UUID,
  p_start_date DATE DEFAULT NULL,
  p_end_date DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.get_promotor_bonus_summary_from_events(
    p_promotor_id,
    p_start_date,
    p_end_date
  );
$$;

CREATE OR REPLACE FUNCTION public.get_promotor_bonus_details(
  p_promotor_id UUID,
  p_start_date DATE DEFAULT NULL,
  p_end_date DATE DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  transaction_id UUID,
  transaction_date DATE,
  product_name TEXT,
  variant_name TEXT,
  price NUMERIC,
  bonus_amount NUMERIC,
  payment_method TEXT,
  leasing_provider TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    sso.id AS transaction_id,
    sso.transaction_date,
    (p.series || ' ' || p.model_name)::TEXT AS product_name,
    TRIM(CONCAT(COALESCE(pv.ram_rom, ''), ' ', COALESCE(pv.color, '')))::TEXT AS variant_name,
    sso.price_at_transaction AS price,
    d.bonus_amount,
    sso.payment_method,
    sso.leasing_provider
  FROM public.get_promotor_bonus_details_from_events(
    p_promotor_id,
    p_start_date,
    p_end_date,
    p_limit,
    p_offset
  ) d
  JOIN public.sales_sell_out sso ON sso.id = d.sales_sell_out_id
  JOIN public.product_variants pv ON pv.id = sso.variant_id
  JOIN public.products p ON p.id = pv.product_id
  ORDER BY sso.transaction_date DESC, sso.created_at DESC, sso.id DESC;
$$;

GRANT EXECUTE ON FUNCTION public.get_promotor_bonus_summary_from_events(UUID, DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_promotor_bonus_details_from_events(UUID, DATE, DATE, INTEGER, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_promotor_bonus_summary(UUID, DATE, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_promotor_bonus_details(UUID, DATE, DATE, INTEGER, INTEGER) TO authenticated;
