-- Wave 2 RLS normalization for operational/supporting tables.
-- Scope:
-- - activity_feed
-- - imei_records
-- - store_inventory
-- - sator_monthly_kpi
-- - sator_rewards

ALTER TABLE IF EXISTS public.activity_feed ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.imei_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.store_inventory ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.sator_monthly_kpi ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.sator_rewards ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  policy_record record;
  target_table text;
BEGIN
  FOREACH target_table IN ARRAY ARRAY[
    'activity_feed',
    'imei_records',
    'store_inventory',
    'sator_monthly_kpi',
    'sator_rewards'
  ]
  LOOP
    FOR policy_record IN
      SELECT p.policyname
      FROM pg_policies p
      WHERE p.schemaname = 'public'
        AND p.tablename = target_table
    LOOP
      EXECUTE format(
        'DROP POLICY IF EXISTS %I ON public.%I',
        policy_record.policyname,
        target_table
      );
    END LOOP;
  END LOOP;
END $$;

CREATE POLICY "activity_feed_select_hierarchy"
ON public.activity_feed
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR public.can_access_promotor(user_id)
  OR public.can_access_sator(user_id)
);

CREATE POLICY "activity_feed_insert_own"
ON public.activity_feed
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
  OR public.is_admin_or_manager_user()
);

CREATE POLICY "activity_feed_update_admin"
ON public.activity_feed
FOR UPDATE
TO authenticated
USING (public.is_admin_or_manager_user())
WITH CHECK (public.is_admin_or_manager_user());

CREATE POLICY "activity_feed_delete_admin"
ON public.activity_feed
FOR DELETE
TO authenticated
USING (public.is_admin_or_manager_user());

CREATE POLICY "imei_records_select_hierarchy"
ON public.imei_records
FOR SELECT
TO authenticated
USING (
  public.can_access_promotor(promotor_id)
  OR public.can_access_store(store_id)
);

CREATE POLICY "imei_records_insert_own"
ON public.imei_records
FOR INSERT
TO authenticated
WITH CHECK (
  (
    public.is_promotor_user()
    AND promotor_id = auth.uid()
    AND public.can_access_store(store_id)
  )
  OR public.is_admin_or_manager_user()
);

CREATE POLICY "imei_records_update_owner_pending"
ON public.imei_records
FOR UPDATE
TO authenticated
USING (
  (
    public.is_promotor_user()
    AND promotor_id = auth.uid()
    AND COALESCE(normalization_status, 'pending') = 'pending'
    AND public.can_access_store(store_id)
  )
  OR public.is_admin_or_manager_user()
)
WITH CHECK (
  (
    public.is_promotor_user()
    AND promotor_id = auth.uid()
    AND public.can_access_store(store_id)
  )
  OR public.is_admin_or_manager_user()
);

CREATE POLICY "imei_records_delete_admin"
ON public.imei_records
FOR DELETE
TO authenticated
USING (public.is_admin_or_manager_user());

CREATE POLICY "store_inventory_select_scope"
ON public.store_inventory
FOR SELECT
TO authenticated
USING (public.can_access_store(store_id));

CREATE POLICY "store_inventory_manage_admin"
ON public.store_inventory
FOR ALL
TO authenticated
USING (public.is_admin_or_manager_user())
WITH CHECK (public.is_admin_or_manager_user());

CREATE POLICY "sator_monthly_kpi_select_hierarchy"
ON public.sator_monthly_kpi
FOR SELECT
TO authenticated
USING (public.can_access_sator(sator_id));

CREATE POLICY "sator_monthly_kpi_manage_admin"
ON public.sator_monthly_kpi
FOR ALL
TO authenticated
USING (public.is_admin_or_manager_user())
WITH CHECK (public.is_admin_or_manager_user());

CREATE POLICY "sator_rewards_select_sensitive"
ON public.sator_rewards
FOR SELECT
TO authenticated
USING (
  sator_id = auth.uid()
  OR public.is_admin_or_manager_user()
);

CREATE POLICY "sator_rewards_manage_admin"
ON public.sator_rewards
FOR ALL
TO authenticated
USING (public.is_admin_or_manager_user())
WITH CHECK (public.is_admin_or_manager_user());
