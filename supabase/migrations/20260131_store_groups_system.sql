-- Store Groups System
-- Admin can group stores (e.g., multiple branches of same owner)
-- System will aggregate data for sell-in, stock, and orders

-- Create store_groups table
CREATE TABLE IF NOT EXISTS store_groups (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_name text NOT NULL UNIQUE,
  description text,
  owner_name text,
  owner_phone text,
  owner_email text,
  is_active boolean DEFAULT true,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW(),
  deleted_at timestamptz
);

-- Add group_id to stores table
ALTER TABLE stores 
ADD COLUMN IF NOT EXISTS group_id uuid REFERENCES store_groups(id);

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_store_groups_updated_at ON store_groups;
CREATE TRIGGER update_store_groups_updated_at
  BEFORE UPDATE ON store_groups
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_stores_group_id ON stores(group_id);

-- Function: Get stores with their group info
CREATE OR REPLACE FUNCTION get_stores_with_groups()
RETURNS TABLE (
  store_id uuid,
  store_name text,
  area text,
  grade text,
  group_id uuid,
  group_name text,
  is_grouped boolean,
  total_stores_in_group bigint
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    s.id as store_id,
    s.store_name,
    s.area,
    s.grade,
    s.group_id,
    sg.group_name,
    (s.group_id IS NOT NULL) as is_grouped,
    CASE 
      WHEN s.group_id IS NOT NULL THEN (
        SELECT COUNT(*) 
        FROM stores 
        WHERE group_id = s.group_id 
        AND deleted_at IS NULL
      )
      ELSE 0
    END as total_stores_in_group
  FROM stores s
  LEFT JOIN store_groups sg ON sg.id = s.group_id AND sg.deleted_at IS NULL
  WHERE s.deleted_at IS NULL
  ORDER BY 
    CASE WHEN sg.group_name IS NULL THEN 1 ELSE 0 END,
    sg.group_name,
    s.store_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get aggregated stock for store group
CREATE OR REPLACE FUNCTION get_group_stock_aggregate(p_group_id uuid)
RETURNS TABLE (
  variant_id uuid,
  product_name text,
  variant_name text,
  total_quantity bigint,
  stores_with_stock bigint,
  total_stores bigint,
  stock_details jsonb
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    pv.id as variant_id,
    p.product_name,
    pv.variant_name,
    COALESCE(SUM(si.quantity), 0) as total_quantity,
    COUNT(DISTINCT CASE WHEN si.quantity > 0 THEN si.store_id END) as stores_with_stock,
    COUNT(DISTINCT s.id) as total_stores,
    jsonb_agg(
      jsonb_build_object(
        'store_id', s.id,
        'store_name', s.store_name,
        'quantity', COALESCE(si.quantity, 0)
      ) ORDER BY s.store_name
    ) as stock_details
  FROM product_variants pv
  JOIN products p ON p.id = pv.product_id
  CROSS JOIN stores s
  LEFT JOIN store_inventory si ON si.variant_id = pv.id AND si.store_id = s.id
  WHERE s.group_id = p_group_id
    AND s.deleted_at IS NULL
    AND p.deleted_at IS NULL
  GROUP BY pv.id, p.product_name, pv.variant_name
  ORDER BY p.product_name, pv.variant_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function: Get group summary for sator
CREATE OR REPLACE FUNCTION get_sator_store_groups(p_sator_id uuid)
RETURNS TABLE (
  group_id uuid,
  group_name text,
  total_stores bigint,
  store_list jsonb,
  total_stock bigint,
  low_stock_count bigint,
  empty_stock_count bigint
) AS $$
BEGIN
  RETURN QUERY
  WITH sator_stores AS (
    SELECT s.id, s.store_name, s.group_id
    FROM stores s
    INNER JOIN assignments_sator_store ass 
      ON ass.store_id = s.id 
      AND ass.sator_id = p_sator_id 
      AND ass.active = true
    WHERE s.deleted_at IS NULL
  )
  SELECT 
    COALESCE(sg.id, '00000000-0000-0000-0000-000000000000'::uuid) as group_id,
    COALESCE(sg.group_name, 'Ungrouped') as group_name,
    COUNT(DISTINCT ss.id) as total_stores,
    jsonb_agg(
      jsonb_build_object(
        'store_id', ss.id,
        'store_name', ss.store_name
      ) ORDER BY ss.store_name
    ) as store_list,
    COALESCE(SUM((
      SELECT COUNT(*) 
      FROM store_inventory si 
      WHERE si.store_id = ss.id
    )), 0) as total_stock,
    COALESCE(SUM((
      SELECT COUNT(*) 
      FROM store_inventory si 
      WHERE si.store_id = ss.id 
      AND si.quantity > 0 
      AND si.quantity < 5
    )), 0) as low_stock_count,
    COALESCE(SUM((
      SELECT COUNT(*) 
      FROM store_inventory si 
      WHERE si.store_id = ss.id 
      AND si.quantity = 0
    )), 0) as empty_stock_count
  FROM sator_stores ss
  LEFT JOIN store_groups sg ON sg.id = ss.group_id AND sg.deleted_at IS NULL
  GROUP BY sg.id, sg.group_name
  ORDER BY 
    CASE WHEN sg.group_name IS NULL THEN 1 ELSE 0 END,
    sg.group_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant permissions
GRANT EXECUTE ON FUNCTION get_stores_with_groups() TO authenticated;
GRANT EXECUTE ON FUNCTION get_group_stock_aggregate(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION get_sator_store_groups(uuid) TO authenticated;

-- Success message
SELECT 'Store groups system created successfully!' as status;
SELECT 'Admin can now create groups and assign stores to groups.' as info;
SELECT 'Functions available:' as info;
SELECT '- get_stores_with_groups(): List all stores with group info' as func;
SELECT '- get_group_stock_aggregate(group_id): Get combined stock for all stores in group' as func;
SELECT '- get_sator_store_groups(sator_id): Get grouped view of sator stores' as func;
