-- Store Groups System
-- Group stores that belong to same owner/brand with multiple branches
-- Example: MAJU MULIA MANDIRI (parent) -> MAHARANI, MCELL (branches)
--          ERAFONE (parent) -> LIPPO, MEGASTORE (branches)

-- Create store_groups table
CREATE TABLE IF NOT EXISTS store_groups (
  id uuid PRIMARY KEY DEFAULT uuid_generate_v4(),
  group_name text NOT NULL UNIQUE,
  description text,
  owner_name text,
  owner_phone text,
  owner_email text,
  created_at timestamptz DEFAULT NOW(),
  updated_at timestamptz DEFAULT NOW(),
  deleted_at timestamptz
);

-- Add group_id to stores table
ALTER TABLE stores 
ADD COLUMN IF NOT EXISTS group_id uuid REFERENCES store_groups(id);

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_stores_group_id ON stores(group_id);

-- Trigger for updated_at
DROP TRIGGER IF EXISTS update_store_groups_updated_at ON store_groups;
CREATE TRIGGER update_store_groups_updated_at
  BEFORE UPDATE ON store_groups
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- Insert common store groups based on existing data
INSERT INTO store_groups (group_name, description) VALUES
  ('MAJU MULIA MANDIRI', 'Grup toko Maju Mulia Mandiri dengan berbagai cabang'),
  ('ERAFONE', 'Grup toko Erafone dengan berbagai cabang'),
  ('SPC', 'Grup toko SPC (Smartphone Center) dengan berbagai cabang')
ON CONFLICT (group_name) DO NOTHING;

-- Auto-assign existing stores to groups based on name patterns
UPDATE stores 
SET group_id = (SELECT id FROM store_groups WHERE group_name = 'MAJU MULIA MANDIRI')
WHERE store_name LIKE 'MAJU MULIA MANDIRI%'
AND group_id IS NULL;

UPDATE stores 
SET group_id = (SELECT id FROM store_groups WHERE group_name = 'ERAFONE')
WHERE store_name LIKE 'ERAFONE%'
AND group_id IS NULL;

UPDATE stores 
SET group_id = (SELECT id FROM store_groups WHERE group_name = 'SPC')
WHERE store_name LIKE 'SPC %'
AND group_id IS NULL;

-- Function to get stores grouped by group
CREATE OR REPLACE FUNCTION get_stores_with_groups()
RETURNS TABLE (
  store_id uuid,
  store_name text,
  area text,
  group_id uuid,
  group_name text,
  total_stores_in_group bigint
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    s.id as store_id,
    s.store_name,
    s.area,
    s.group_id,
    sg.group_name,
    (SELECT COUNT(*) FROM stores WHERE group_id = s.group_id AND deleted_at IS NULL) as total_stores_in_group
  FROM stores s
  LEFT JOIN store_groups sg ON sg.id = s.group_id
  WHERE s.deleted_at IS NULL
  ORDER BY 
    CASE WHEN sg.group_name IS NULL THEN 1 ELSE 0 END,
    sg.group_name,
    s.store_name;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION get_stores_with_groups() TO authenticated;

-- Verify grouping
SELECT 'Store groups created!' as status;
SELECT 'Grouped stores:' as info;
SELECT 
  sg.group_name,
  COUNT(*) as total_stores,
  string_agg(s.store_name, ', ' ORDER BY s.store_name) as stores
FROM stores s
JOIN store_groups sg ON sg.id = s.group_id
WHERE s.deleted_at IS NULL
GROUP BY sg.id, sg.group_name
ORDER BY sg.group_name;

SELECT 'Ungrouped stores:' as info;
SELECT store_name 
FROM stores 
WHERE group_id IS NULL 
AND deleted_at IS NULL
ORDER BY store_name;
