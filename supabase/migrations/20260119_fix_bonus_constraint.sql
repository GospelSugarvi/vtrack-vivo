-- Fix bonus_type constraint to include 'ratio'

-- 1. Drop existing constraints
ALTER TABLE bonus_rules DROP CONSTRAINT IF EXISTS bonus_rules_bonus_type_check;
ALTER TABLE bonus_rules DROP CONSTRAINT IF EXISTS valid_range_bonus;

-- 2. Add updated constraint with 'ratio' included
ALTER TABLE bonus_rules ADD CONSTRAINT bonus_rules_bonus_type_check 
  CHECK (bonus_type = ANY (ARRAY['range', 'flat', 'ratio']));

-- 3. Add updated validation constraint
ALTER TABLE bonus_rules ADD CONSTRAINT valid_bonus_rule CHECK (
  (bonus_type = 'range' AND min_price IS NOT NULL AND bonus_official IS NOT NULL) 
  OR (bonus_type = 'flat' AND product_id IS NOT NULL AND (flat_bonus IS NOT NULL OR bonus_official IS NOT NULL))
  OR (bonus_type = 'ratio' AND product_id IS NOT NULL AND ratio_value IS NOT NULL)
);
