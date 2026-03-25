-- Migration: 20260119_add_network_type.sql
-- Add 4G/5G network type to products

ALTER TABLE products ADD COLUMN IF NOT EXISTS network_type text DEFAULT '4G' CHECK (network_type IN ('4G', '5G'));

-- Create index for filtering
CREATE INDEX IF NOT EXISTS idx_products_network_type ON products(network_type);

COMMENT ON COLUMN products.network_type IS '4G or 5G network type for the product';
