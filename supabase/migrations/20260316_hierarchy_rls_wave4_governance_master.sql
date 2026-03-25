-- Wave 4: governance lockdown and master-table hardening.
-- Scope:
-- - governance tables: audit_logs, activity_logs, stock_daily_snapshot
-- - admin/master tables with permissive RLS

ALTER TABLE IF EXISTS public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.stock_daily_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.bonus_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.kpi_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.point_ranges ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.weekly_targets ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.special_rewards ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.special_focus_bundles ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.special_focus_bundle_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.reward_bundles ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.reward_bundle_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.fokus_bundles ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.fokus_products ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.fokus_targets ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  policy_record record;
  target_table text;
BEGIN
  FOREACH target_table IN ARRAY ARRAY[
    'audit_logs',
    'activity_logs',
    'stock_daily_snapshot',
    'bonus_rules',
    'kpi_settings',
    'point_ranges',
    'weekly_targets',
    'special_rewards',
    'special_focus_bundles',
    'special_focus_bundle_products',
    'reward_bundles',
    'reward_bundle_products',
    'fokus_bundles',
    'fokus_products',
    'fokus_targets'
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

CREATE POLICY "audit_logs_admin_only"
ON public.audit_logs
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "activity_logs_admin_only"
ON public.activity_logs
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "stock_daily_snapshot_admin_only"
ON public.stock_daily_snapshot
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "bonus_rules_read_authenticated"
ON public.bonus_rules
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "bonus_rules_manage_admin"
ON public.bonus_rules
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "kpi_settings_read_authenticated"
ON public.kpi_settings
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "kpi_settings_manage_admin"
ON public.kpi_settings
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "point_ranges_read_authenticated"
ON public.point_ranges
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "point_ranges_manage_admin"
ON public.point_ranges
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "weekly_targets_read_authenticated"
ON public.weekly_targets
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "weekly_targets_manage_admin"
ON public.weekly_targets
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "special_rewards_read_authenticated"
ON public.special_rewards
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "special_rewards_manage_admin"
ON public.special_rewards
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "special_focus_bundles_read_authenticated"
ON public.special_focus_bundles
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "special_focus_bundles_manage_admin"
ON public.special_focus_bundles
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "special_focus_bundle_products_read_authenticated"
ON public.special_focus_bundle_products
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "special_focus_bundle_products_manage_admin"
ON public.special_focus_bundle_products
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "reward_bundles_read_authenticated"
ON public.reward_bundles
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "reward_bundles_manage_admin"
ON public.reward_bundles
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "reward_bundle_products_read_authenticated"
ON public.reward_bundle_products
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "reward_bundle_products_manage_admin"
ON public.reward_bundle_products
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "fokus_bundles_read_authenticated"
ON public.fokus_bundles
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "fokus_bundles_manage_admin"
ON public.fokus_bundles
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "fokus_products_read_authenticated"
ON public.fokus_products
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "fokus_products_manage_admin"
ON public.fokus_products
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());

CREATE POLICY "fokus_targets_read_own_or_elevated"
ON public.fokus_targets
FOR SELECT
TO authenticated
USING (
  user_id = auth.uid()
  OR public.is_elevated_user()
);

CREATE POLICY "fokus_targets_manage_admin"
ON public.fokus_targets
FOR ALL
TO authenticated
USING (public.is_admin_user())
WITH CHECK (public.is_admin_user());
