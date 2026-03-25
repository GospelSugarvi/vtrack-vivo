-- RLS Policies for Hierarchy Tables - Admin Full Access

-- assignments_promotor_store
DROP POLICY IF EXISTS "Admin manage promotor_store" ON assignments_promotor_store;
CREATE POLICY "Admin manage promotor_store" ON assignments_promotor_store 
FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- hierarchy_manager_spv
ALTER TABLE hierarchy_manager_spv ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin manage manager_spv" ON hierarchy_manager_spv;
CREATE POLICY "Admin manage manager_spv" ON hierarchy_manager_spv 
FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- hierarchy_spv_sator
ALTER TABLE hierarchy_spv_sator ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin manage spv_sator" ON hierarchy_spv_sator;
CREATE POLICY "Admin manage spv_sator" ON hierarchy_spv_sator 
FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- hierarchy_sator_promotor
ALTER TABLE hierarchy_sator_promotor ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin manage sator_promotor" ON hierarchy_sator_promotor;
CREATE POLICY "Admin manage sator_promotor" ON hierarchy_sator_promotor 
FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- Also allow read for relevant roles
DROP POLICY IF EXISTS "SPV read own sators" ON hierarchy_spv_sator;
CREATE POLICY "SPV read own sators" ON hierarchy_spv_sator 
FOR SELECT USING (spv_id = auth.uid());

DROP POLICY IF EXISTS "SATOR read own promotors" ON hierarchy_sator_promotor;
CREATE POLICY "SATOR read own promotors" ON hierarchy_sator_promotor 
FOR SELECT USING (sator_id = auth.uid());

DROP POLICY IF EXISTS "Promotor read own stores" ON assignments_promotor_store;
CREATE POLICY "Promotor read own stores" ON assignments_promotor_store 
FOR SELECT USING (promotor_id = auth.uid());
