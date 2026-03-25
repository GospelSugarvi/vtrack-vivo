-- =====================================================
-- FIX PRODUCT MAPPING - INCLUDE SERIES
-- Created: 2026-02-05
-- =====================================================

-- Improve `get_products_for_mapping` to include Series in the name logic
-- This helps matching "V60 LITE 5G" if "5G" is stored in series column
CREATE OR REPLACE FUNCTION get_products_for_mapping()
RETURNS JSON
LANGUAGE sql
SECURITY DEFINER
AS $$
  SELECT json_agg(
    json_build_object(
      'product_id', p.id,
      'variant_id', pv.id,
      -- Concatenate Model + Series + RAM + Color properly
      'full_name', TRIM(REGEXP_REPLACE(p.model_name || ' ' || COALESCE(p.series, '') || ' ' || COALESCE(pv.ram_rom, '') || ' ' || COALESCE(pv.color, ''), '\s+', ' ', 'g')),
      'product_name', p.model_name,
      'series', p.series,
      'variant_name', pv.ram_rom,
      'color', pv.color
    )
  )
  FROM products p
  JOIN product_variants pv ON p.id = pv.product_id
  WHERE p.status = 'active' AND pv.active = true;
$$;
