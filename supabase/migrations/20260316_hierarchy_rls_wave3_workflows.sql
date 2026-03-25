-- Wave 3 RLS hardening for workflow and remaining permissive policies.
-- Scope:
-- - schedules
-- - schedule_requests
-- - sell_out_void_requests
-- - message_reads
-- - stock_rules
-- - users
-- - stores

ALTER TABLE IF EXISTS public.schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.schedule_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.sell_out_void_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.message_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.stock_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.stores ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  policy_record record;
  target_table text;
BEGIN
  FOREACH target_table IN ARRAY ARRAY[
    'schedules',
    'schedule_requests',
    'sell_out_void_requests',
    'message_reads',
    'stock_rules',
    'users',
    'stores'
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

CREATE POLICY "schedules_select_hierarchy"
ON public.schedules
FOR SELECT
TO authenticated
USING (
  promotor_id = auth.uid()
  OR public.can_access_promotor(promotor_id)
);

CREATE POLICY "schedules_insert_own"
ON public.schedules
FOR INSERT
TO authenticated
WITH CHECK (
  (
    public.is_promotor_user()
    AND promotor_id = auth.uid()
    AND status IN ('draft', 'submitted')
  )
  OR public.is_admin_or_manager_user()
);

CREATE POLICY "schedules_update_own_or_reviewer"
ON public.schedules
FOR UPDATE
TO authenticated
USING (
  (
    public.is_promotor_user()
    AND promotor_id = auth.uid()
  )
  OR public.can_access_promotor(promotor_id)
  OR public.is_admin_or_manager_user()
)
WITH CHECK (
  (
    public.is_promotor_user()
    AND promotor_id = auth.uid()
  )
  OR public.can_access_promotor(promotor_id)
  OR public.is_admin_or_manager_user()
);

CREATE POLICY "schedules_delete_own_or_admin"
ON public.schedules
FOR DELETE
TO authenticated
USING (
  (public.is_promotor_user() AND promotor_id = auth.uid())
  OR public.is_admin_or_manager_user()
);

CREATE POLICY "schedule_requests_select_hierarchy"
ON public.schedule_requests
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR public.can_access_promotor(user_id)
);

CREATE POLICY "schedule_requests_insert_own"
ON public.schedule_requests
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND status = 'pending'
  AND approved_by IS NULL
  AND approved_at IS NULL
);

CREATE POLICY "schedule_requests_update_reviewer"
ON public.schedule_requests
FOR UPDATE
TO authenticated
USING (
  public.can_access_promotor(user_id)
  OR public.is_admin_or_manager_user()
)
WITH CHECK (
  public.can_access_promotor(user_id)
  OR public.is_admin_or_manager_user()
);

CREATE POLICY "sell_out_void_requests_select_hierarchy"
ON public.sell_out_void_requests
FOR SELECT
TO authenticated
USING (
  requested_by = auth.uid()
  OR promotor_id = auth.uid()
  OR public.can_access_promotor(promotor_id)
);

CREATE POLICY "sell_out_void_requests_insert_own"
ON public.sell_out_void_requests
FOR INSERT
TO authenticated
WITH CHECK (
  requested_by = auth.uid()
  AND promotor_id = auth.uid()
  AND EXISTS (
    SELECT 1
    FROM public.sales_sell_out so
    WHERE so.id = sale_id
      AND so.promotor_id = auth.uid()
      AND so.deleted_at IS NULL
  )
);

CREATE POLICY "message_reads_manage_own"
ON public.message_reads
FOR ALL
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY "stock_rules_read_authenticated"
ON public.stock_rules
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "stock_rules_manage_admin"
ON public.stock_rules
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "users_read_authenticated"
ON public.users
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "users_manage_admin"
ON public.users
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "stores_read_authenticated"
ON public.stores
FOR SELECT
TO authenticated
USING (auth.role() = 'authenticated');

CREATE POLICY "stores_manage_admin"
ON public.stores
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());
