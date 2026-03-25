-- Server-driven sell-in achievement periods based on finalized transactions.

DROP FUNCTION IF EXISTS public.get_sellin_achievement(UUID, TEXT);
DROP FUNCTION IF EXISTS public.get_sellin_achievement(UUID, TEXT, UUID);
DROP FUNCTION IF EXISTS public.get_sellin_achievement(UUID, TEXT, UUID, DATE, DATE);

CREATE OR REPLACE FUNCTION public.get_sellin_achievement(
  p_sator_id UUID,
  p_view_mode TEXT DEFAULT 'daily',
  p_store_id UUID DEFAULT NULL,
  p_start_date DATE DEFAULT NULL,
  p_end_date DATE DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_mode TEXT := LOWER(COALESCE(p_view_mode, 'daily'));
  v_result JSON;
  v_start DATE;
  v_end DATE;
  v_label TEXT;
BEGIN
  IF v_mode NOT IN ('daily', 'weekly', 'monthly') THEN
    RAISE EXCEPTION 'p_view_mode must be daily, weekly, or monthly';
  END IF;

  v_end := COALESCE(p_end_date, CURRENT_DATE);
  IF p_start_date IS NOT NULL THEN
    v_start := p_start_date;
  ELSIF v_mode = 'daily' THEN
    v_start := v_end - INTERVAL '29 days';
  ELSIF v_mode = 'weekly' THEN
    v_start := v_end - INTERVAL '83 days';
  ELSE
    v_start := (DATE_TRUNC('month', v_end::timestamp)::DATE - INTERVAL '11 months')::DATE;
  END IF;

  IF v_start > v_end THEN
    RAISE EXCEPTION 'p_start_date must be before or equal to p_end_date';
  END IF;

  v_label := CONCAT(
    TO_CHAR(v_start, 'DD Mon YYYY'),
    ' - ',
    TO_CHAR(v_end, 'DD Mon YYYY')
  );

  IF v_mode = 'daily' THEN
    WITH rows AS (
      SELECT
        s.transaction_date AS start_date,
        s.transaction_date AS end_date,
        TO_CHAR(s.transaction_date, 'YYYY-MM-DD') AS period_key,
        COALESCE(SUM(s.qty), 0)::INTEGER AS total_units,
        COALESCE(SUM(s.total_value), 0)::NUMERIC AS total_value,
        COUNT(DISTINCT COALESCE(s.source_order_id::TEXT, s.id::TEXT))::INTEGER AS total_orders
      FROM public.sales_sell_in s
      WHERE s.sator_id = p_sator_id
        AND s.deleted_at IS NULL
        AND (p_store_id IS NULL OR s.store_id = p_store_id)
        AND s.transaction_date BETWEEN v_start AND v_end
      GROUP BY s.transaction_date
      ORDER BY s.transaction_date DESC
    )
    SELECT json_build_object(
      'view_mode', v_mode,
      'summary', json_build_object(
        'period_label', v_label,
        'store_id', p_store_id,
        'start_date', v_start,
        'end_date', v_end,
        'total_units', COALESCE(SUM(r.total_units), 0),
        'total_value', COALESCE(SUM(r.total_value), 0),
        'total_orders', COALESCE(SUM(r.total_orders), 0)
      ),
      'rows', COALESCE(
        json_agg(
          json_build_object(
            'period_key', r.period_key,
            'start_date', r.start_date,
            'end_date', r.end_date,
            'total_units', r.total_units,
            'total_value', r.total_value,
            'total_orders', r.total_orders
          )
          ORDER BY r.start_date DESC
        ),
        '[]'::json
      )
    ) INTO v_result
    FROM rows r;
  ELSIF v_mode = 'weekly' THEN
    WITH rows AS (
      SELECT
        DATE_TRUNC('week', s.transaction_date::timestamp)::DATE AS start_date,
        (DATE_TRUNC('week', s.transaction_date::timestamp)::DATE + 6) AS end_date,
        TO_CHAR(DATE_TRUNC('week', s.transaction_date::timestamp)::DATE, 'YYYY-MM-DD') AS period_key,
        COALESCE(SUM(s.qty), 0)::INTEGER AS total_units,
        COALESCE(SUM(s.total_value), 0)::NUMERIC AS total_value,
        COUNT(DISTINCT COALESCE(s.source_order_id::TEXT, s.id::TEXT))::INTEGER AS total_orders
      FROM public.sales_sell_in s
      WHERE s.sator_id = p_sator_id
        AND s.deleted_at IS NULL
        AND (p_store_id IS NULL OR s.store_id = p_store_id)
        AND s.transaction_date BETWEEN v_start AND v_end
      GROUP BY 1, 2, 3
      ORDER BY 1 DESC
    )
    SELECT json_build_object(
      'view_mode', v_mode,
      'summary', json_build_object(
        'period_label', v_label,
        'store_id', p_store_id,
        'start_date', v_start,
        'end_date', v_end,
        'total_units', COALESCE(SUM(r.total_units), 0),
        'total_value', COALESCE(SUM(r.total_value), 0),
        'total_orders', COALESCE(SUM(r.total_orders), 0)
      ),
      'rows', COALESCE(
        json_agg(
          json_build_object(
            'period_key', r.period_key,
            'start_date', r.start_date,
            'end_date', r.end_date,
            'total_units', r.total_units,
            'total_value', r.total_value,
            'total_orders', r.total_orders
          )
          ORDER BY r.start_date DESC
        ),
        '[]'::json
      )
    ) INTO v_result
    FROM rows r;
  ELSE
    WITH rows AS (
      SELECT
        DATE_TRUNC('month', s.transaction_date::timestamp)::DATE AS start_date,
        (DATE_TRUNC('month', s.transaction_date::timestamp)::DATE + INTERVAL '1 month - 1 day')::DATE AS end_date,
        TO_CHAR(DATE_TRUNC('month', s.transaction_date::timestamp)::DATE, 'YYYY-MM-DD') AS period_key,
        COALESCE(SUM(s.qty), 0)::INTEGER AS total_units,
        COALESCE(SUM(s.total_value), 0)::NUMERIC AS total_value,
        COUNT(DISTINCT COALESCE(s.source_order_id::TEXT, s.id::TEXT))::INTEGER AS total_orders
      FROM public.sales_sell_in s
      WHERE s.sator_id = p_sator_id
        AND s.deleted_at IS NULL
        AND (p_store_id IS NULL OR s.store_id = p_store_id)
        AND s.transaction_date BETWEEN v_start AND v_end
      GROUP BY 1, 2, 3
      ORDER BY 1 DESC
    )
    SELECT json_build_object(
      'view_mode', v_mode,
      'summary', json_build_object(
        'period_label', v_label,
        'store_id', p_store_id,
        'start_date', v_start,
        'end_date', v_end,
        'total_units', COALESCE(SUM(r.total_units), 0),
        'total_value', COALESCE(SUM(r.total_value), 0),
        'total_orders', COALESCE(SUM(r.total_orders), 0)
      ),
      'rows', COALESCE(
        json_agg(
          json_build_object(
            'period_key', r.period_key,
            'start_date', r.start_date,
            'end_date', r.end_date,
            'total_units', r.total_units,
            'total_value', r.total_value,
            'total_orders', r.total_orders
          )
          ORDER BY r.start_date DESC
        ),
        '[]'::json
      )
    ) INTO v_result
    FROM rows r;
  END IF;

  RETURN COALESCE(
    v_result,
    json_build_object(
      'view_mode', v_mode,
      'summary', json_build_object(
        'period_label', v_label,
        'store_id', p_store_id,
        'start_date', v_start,
        'end_date', v_end,
        'total_units', 0,
        'total_value', 0,
        'total_orders', 0
      ),
      'rows', '[]'::json
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_sellin_achievement(UUID, TEXT, UUID, DATE, DATE) TO authenticated;

DROP FUNCTION IF EXISTS public.get_sellin_achievement_day_detail(UUID, DATE, UUID);

CREATE OR REPLACE FUNCTION public.get_sellin_achievement_day_detail(
  p_sator_id UUID,
  p_period_date DATE,
  p_store_id UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH base AS (
    SELECT
      s.store_id,
      st.store_name,
      s.source_order_id,
      p.model_name AS product_name,
      pv.ram_rom AS variant,
      pv.color,
      s.qty,
      s.total_value
    FROM public.sales_sell_in s
    JOIN public.stores st ON st.id = s.store_id
    JOIN public.product_variants pv ON pv.id = s.variant_id
    JOIN public.products p ON p.id = pv.product_id
    WHERE s.sator_id = p_sator_id
      AND s.deleted_at IS NULL
      AND s.transaction_date = p_period_date
      AND (p_store_id IS NULL OR s.store_id = p_store_id)
  ),
  item_rows AS (
    SELECT
      b.store_id,
      b.store_name,
      b.product_name,
      b.variant,
      b.color,
      COALESCE(SUM(b.qty), 0)::INTEGER AS total_qty,
      COALESCE(SUM(b.total_value), 0)::NUMERIC AS total_value
    FROM base b
    GROUP BY b.store_id, b.store_name, b.product_name, b.variant, b.color
  ),
  store_rows AS (
    SELECT
      b.store_id,
      b.store_name,
      COUNT(DISTINCT COALESCE(b.source_order_id::TEXT, b.store_id::TEXT || ':' || p_period_date::TEXT))::INTEGER AS total_orders,
      COALESCE(SUM(b.qty), 0)::INTEGER AS total_units,
      COALESCE(SUM(b.total_value), 0)::NUMERIC AS total_value
    FROM base b
    GROUP BY b.store_id, b.store_name
  )
  SELECT json_build_object(
    'period_date', p_period_date,
    'stores', COALESCE(
      json_agg(
        json_build_object(
          'store_id', s.store_id,
          'store_name', s.store_name,
          'total_orders', s.total_orders,
          'total_units', s.total_units,
          'total_value', s.total_value,
          'items', COALESCE(
            (
              SELECT json_agg(
                json_build_object(
                  'product_name', i.product_name,
                  'variant', i.variant,
                  'color', i.color,
                  'total_qty', i.total_qty,
                  'total_value', i.total_value
                )
                ORDER BY i.product_name, i.variant, i.color
              )
              FROM item_rows i
              WHERE i.store_id = s.store_id
            ),
            '[]'::json
          )
        )
        ORDER BY s.store_name
      ),
      '[]'::json
    )
  )
  FROM store_rows s;
$$;

GRANT EXECUTE ON FUNCTION public.get_sellin_achievement_day_detail(UUID, DATE, UUID) TO authenticated;
