-- Add unique constraints for hierarchy tables to enable upsert

-- Manager -> SPV
ALTER TABLE hierarchy_manager_spv 
DROP CONSTRAINT IF EXISTS hierarchy_manager_spv_unique;

ALTER TABLE hierarchy_manager_spv 
ADD CONSTRAINT hierarchy_manager_spv_unique UNIQUE (manager_id, spv_id);

-- SPV -> SATOR
ALTER TABLE hierarchy_spv_sator 
DROP CONSTRAINT IF EXISTS hierarchy_spv_sator_unique;

ALTER TABLE hierarchy_spv_sator 
ADD CONSTRAINT hierarchy_spv_sator_unique UNIQUE (spv_id, sator_id);

-- SATOR -> Promotor
ALTER TABLE hierarchy_sator_promotor 
DROP CONSTRAINT IF EXISTS hierarchy_sator_promotor_unique;

ALTER TABLE hierarchy_sator_promotor 
ADD CONSTRAINT hierarchy_sator_promotor_unique UNIQUE (sator_id, promotor_id);

-- Promotor -> Store
ALTER TABLE assignments_promotor_store 
DROP CONSTRAINT IF EXISTS assignments_promotor_store_unique;

ALTER TABLE assignments_promotor_store 
ADD CONSTRAINT assignments_promotor_store_unique UNIQUE (promotor_id, store_id);
