DROP FUNCTION IF EXISTS public.get_store_recommendations(uuid, uuid);

CREATE OR REPLACE FUNCTION public.get_sell_in_order_composer_snapshot(
  p_mode text DEFAULT 'recommendation',
  p_store_id uuid DEFAULT NULL,
  p_group_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_actor_id uuid := auth.uid();
  v_actor public.users%rowtype;
  v_mode text := lower(trim(coalesce(p_mode, 'recommendation')));
  v_stores jsonb := '[]'::jsonb;
  v_rows_source jsonb := '[]'::jsonb;
  v_rows jsonb := '[]'::jsonb;
  v_group_name text := '';
  v_selected_store_id uuid;
  v_selected_store_name text := 'Pilih toko';
BEGIN
  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;

  IF v_mode NOT IN ('recommendation', 'manual') THEN
    RAISE EXCEPTION 'Mode tidak valid.';
  END IF;

  SELECT *
  INTO v_actor
  FROM public.users
  WHERE id = v_actor_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Profil user tidak ditemukan.';
  END IF;

  IF v_actor.role IS DISTINCT FROM 'sator'::public.user_role
     AND NOT public.is_elevated_user() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;

  v_stores := COALESCE(public.get_store_stock_status(v_actor_id)::jsonb, '[]'::jsonb);

  IF p_group_id IS NOT NULL THEN
    SELECT COALESCE(sg.group_name, 'Grup Toko')
    INTO v_group_name
    FROM public.store_groups sg
    WHERE sg.id = p_group_id;

    v_rows_source := COALESCE(
      public.get_group_store_recommendations(p_group_id)::jsonb,
      '[]'::jsonb
    );
    v_selected_store_name := COALESCE(NULLIF(v_group_name, ''), 'Grup Toko');
  ELSE
    IF p_store_id IS NOT NULL THEN
      v_selected_store_id := p_store_id;
    ELSE
      SELECT NULLIF(x ->> 'store_id', '')::uuid
      INTO v_selected_store_id
      FROM jsonb_array_elements(v_stores) x
      LIMIT 1;
    END IF;

    IF v_selected_store_id IS NOT NULL THEN
      SELECT COALESCE(
        (
          SELECT NULLIF(x ->> 'store_name', '')
          FROM jsonb_array_elements(v_stores) x
          WHERE NULLIF(x ->> 'store_id', '')::uuid = v_selected_store_id
          LIMIT 1
        ),
        (
          SELECT st.store_name
          FROM public.stores st
          WHERE st.id = v_selected_store_id
            AND st.deleted_at IS NULL
          LIMIT 1
        ),
        'Toko'
      )
      INTO v_selected_store_name;

      IF NOT EXISTS (
        SELECT 1
        FROM jsonb_array_elements(v_stores) x
        WHERE NULLIF(x ->> 'store_id', '')::uuid = v_selected_store_id
      ) THEN
        v_stores := jsonb_build_array(
          jsonb_build_object(
            'store_id', v_selected_store_id,
            'store_name', v_selected_store_name,
            'group_name', '',
            'empty_count', 0,
            'low_count', 0
          )
        ) || v_stores;
      END IF;

      v_rows_source := COALESCE(
        public.get_store_recommendations(v_selected_store_id)::jsonb,
        '[]'::jsonb
      );
    END IF;
  END IF;

  v_rows := COALESCE((
    WITH raw_rows AS (
      SELECT
        x.group_id,
        x.group_name,
        x.representative_store_id,
        x.variant_id,
        x.product_id,
        x.product_name,
        x.variant,
        x.color,
        x.price,
        x.modal,
        x.network_type,
        x.series,
        x.current_stock,
        x.min_stock,
        x.shortage_qty,
        x.warehouse_stock,
        x.available_gudang,
        x.order_qty,
        x.unfulfilled_qty,
        x.can_fulfill,
        x.total_stores,
        x.store_breakdown,
        x.status,
        x.recommendation_status
      FROM jsonb_to_recordset(v_rows_source) AS x(
        group_id uuid,
        group_name text,
        representative_store_id uuid,
        variant_id uuid,
        product_id uuid,
        product_name text,
        variant text,
        color text,
        price numeric,
        modal numeric,
        network_type text,
        series text,
        current_stock integer,
        min_stock integer,
        shortage_qty integer,
        warehouse_stock integer,
        available_gudang integer,
        order_qty integer,
        unfulfilled_qty integer,
        can_fulfill boolean,
        total_stores integer,
        store_breakdown jsonb,
        status text,
        recommendation_status text
      )
    ),
    normalized AS (
      SELECT
        rr.group_id,
        rr.group_name,
        rr.representative_store_id,
        rr.variant_id,
        rr.product_id,
        COALESCE(rr.product_name, 'Produk') AS product_name,
        COALESCE(rr.network_type, '') AS network_type,
        COALESCE(rr.series, '') AS series,
        COALESCE(rr.variant, '-') AS variant,
        COALESCE(rr.color, '-') AS color,
        COALESCE(rr.price, 0) AS price,
        COALESCE(rr.modal, 0) AS modal,
        COALESCE(rr.current_stock, 0) AS current_stock,
        COALESCE(rr.min_stock, 0) AS min_stock,
        COALESCE(rr.shortage_qty, 0) AS shortage_qty,
        COALESCE(rr.warehouse_stock, 0) AS warehouse_stock,
        COALESCE(rr.available_gudang, COALESCE(rr.warehouse_stock, 0)) AS available_gudang,
        COALESCE(rr.order_qty, 0) AS order_qty,
        COALESCE(rr.unfulfilled_qty, 0) AS unfulfilled_qty,
        COALESCE(rr.can_fulfill, false) AS can_fulfill,
        COALESCE(rr.total_stores, 0) AS total_stores,
        COALESCE(rr.store_breakdown, '[]'::jsonb) AS store_breakdown,
        COALESCE(rr.status, 'CUKUP') AS status,
        COALESCE(rr.recommendation_status, '') AS recommendation_status,
        CASE
          WHEN v_mode = 'recommendation' THEN COALESCE(rr.order_qty, 0)
          ELSE 0
        END AS selected_qty
      FROM raw_rows rr
      WHERE v_mode <> 'recommendation'
         OR COALESCE(rr.order_qty, 0) > 0
    )
    SELECT jsonb_agg(
      jsonb_build_object(
        'group_id', n.group_id,
        'group_name', n.group_name,
        'representative_store_id', n.representative_store_id,
        'variant_id', n.variant_id,
        'product_id', n.product_id,
        'product_name', n.product_name,
        'network_type', n.network_type,
        'series', n.series,
        'variant', n.variant,
        'color', n.color,
        'price', n.price,
        'modal', n.modal,
        'current_stock', n.current_stock,
        'min_stock', n.min_stock,
        'shortage_qty', n.shortage_qty,
        'warehouse_stock', n.warehouse_stock,
        'available_gudang', n.available_gudang,
        'order_qty', n.order_qty,
        'unfulfilled_qty', n.unfulfilled_qty,
        'can_fulfill', n.can_fulfill,
        'total_stores', n.total_stores,
        'store_breakdown', n.store_breakdown,
        'status', n.status,
        'recommendation_status', n.recommendation_status,
        'selected_qty', n.selected_qty
      )
      ORDER BY
        n.order_qty DESC,
        n.product_name,
        n.network_type,
        n.variant,
        n.color
    )
    FROM normalized n
  ), '[]'::jsonb);

  RETURN jsonb_build_object(
    'current_user_name', COALESCE(NULLIF(TRIM(v_actor.full_name), ''), 'SATOR'),
    'stores', COALESCE(v_stores, '[]'::jsonb),
    'selected_store_id', v_selected_store_id,
    'selected_store_name', v_selected_store_name,
    'rows', COALESCE(v_rows, '[]'::jsonb)
  );
END;
$$;
