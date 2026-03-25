create or replace function public.get_sator_home_snapshot(p_sator_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_profile jsonb := '{}'::jsonb;
  v_summary jsonb := '{}'::jsonb;
  v_promotor_cards jsonb := '{}'::jsonb;
  v_period_id uuid;
  v_focus_products jsonb := '[]'::jsonb;
begin
  select jsonb_build_object(
    'nickname', nullif(trim(coalesce(u.nickname, '')), ''),
    'full_name', coalesce(u.full_name, 'SATOR'),
    'area', coalesce(u.area, '-'),
    'role', 'SATOR'
  )
  into v_profile
  from public.users u
  where u.id = p_sator_id;

  v_summary := coalesce(public.get_sator_home_summary(p_sator_id)::jsonb, '{}'::jsonb);
  v_promotor_cards := coalesce(public.get_sator_home_promotor_cards(p_sator_id)::jsonb, '{}'::jsonb);

  v_period_id := nullif(coalesce(v_summary #>> '{period,id}', ''), '')::uuid;

  if v_period_id is not null then
    select coalesce(jsonb_agg(to_jsonb(fp)), '[]'::jsonb)
    into v_focus_products
    from public.get_fokus_products_by_period(v_period_id) fp;
  end if;

  return jsonb_build_object(
    'profile', v_profile,
    'period', coalesce(v_summary -> 'period', '{}'::jsonb),
    'counts', coalesce(v_summary -> 'counts', '{}'::jsonb),
    'daily', coalesce(v_summary -> 'daily', '{}'::jsonb),
    'weekly', coalesce(v_summary -> 'weekly', '{}'::jsonb),
    'monthly', coalesce(v_summary -> 'monthly', '{}'::jsonb),
    'agenda', coalesce(v_summary -> 'agenda', '[]'::jsonb),
    'daily_promotors', coalesce(v_promotor_cards -> 'daily', '[]'::jsonb),
    'weekly_promotors', coalesce(v_promotor_cards -> 'weekly', '[]'::jsonb),
    'monthly_promotors', coalesce(v_promotor_cards -> 'monthly', '[]'::jsonb),
    'focus_products', v_focus_products
  );
end;
$$;

grant execute on function public.get_sator_home_snapshot(uuid) to authenticated;
