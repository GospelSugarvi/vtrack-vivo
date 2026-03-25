-- Fix RLS policy for dashboard_performance_metrics
-- Allow INSERT from trigger when sales_sell_out is created

-- Drop existing policies
DROP POLICY IF EXISTS "Metrics own" ON dashboard_performance_metrics;
DROP POLICY IF EXISTS "Promotor Own Metrics" ON dashboard_performance_metrics;
DROP POLICY IF EXISTS "Sator Team Metrics" ON dashboard_performance_metrics;

-- Allow users to read their own metrics
CREATE POLICY "Users can read own metrics"
ON dashboard_performance_metrics FOR SELECT
TO authenticated
USING (user_id = auth.uid());

-- Allow INSERT/UPDATE from authenticated users (for trigger)
-- This is needed because trigger runs in user context
CREATE POLICY "Allow metrics upsert"
ON dashboard_performance_metrics FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Allow SATOR to read team metrics
CREATE POLICY "Sator can read team metrics"
ON dashboard_performance_metrics FOR SELECT
TO authenticated
USING (
  user_id IN (
    SELECT promotor_id 
    FROM hierarchy_sator_promotor 
    WHERE sator_id = auth.uid() AND active = true
  )
);

-- Allow admin to read all
CREATE POLICY "Admin can read all metrics"
ON dashboard_performance_metrics FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid() AND role = 'admin'
  )
);
