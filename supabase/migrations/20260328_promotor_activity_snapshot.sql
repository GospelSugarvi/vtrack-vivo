create or replace function public.get_promotor_activity_snapshot(
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_target_date date := coalesce(p_date, current_date);
  v_day_start timestamptz := v_target_date::timestamp;
  v_day_end timestamptz := (v_target_date + 1)::timestamp;
  v_month_start date := date_trunc('month', v_target_date)::date;
  v_month_end date := (date_trunc('month', v_target_date) + interval '1 month')::date;
begin
  if v_user_id is null then
    raise exception 'Unauthorized';
  end if;

  return (
    with attendance_row as (
      select
        a.id,
        a.created_at,
        a.main_attendance_status
      from public.attendance a
      where a.user_id = v_user_id
        and a.attendance_date = v_target_date
      order by a.clock_in desc nulls last, a.created_at desc
      limit 1
    ),
    clock_out_row as (
      select
        a.id,
        a.clock_out as created_at
      from public.attendance a
      where a.user_id = v_user_id
        and a.attendance_date = v_target_date
        and a.clock_out is not null
      order by a.clock_out desc
      limit 1
    ),
    sell_out_rows as (
      select
        s.id,
        s.price_at_transaction,
        s.created_at
      from public.sales_sell_out s
      where s.promotor_id = v_user_id
        and s.deleted_at is null
        and s.transaction_date = v_target_date
      order by s.created_at desc
    ),
    latest_void_rows as (
      select distinct on (r.sale_id)
        r.sale_id,
        r.status,
        r.requested_at
      from public.sell_out_void_requests r
      where r.sale_id in (select sr.id from sell_out_rows sr)
      order by r.sale_id, r.requested_at desc
    ),
    stock_input_rows as (
      select
        sml.id,
        sml.moved_at
      from public.stock_movement_log sml
      where sml.moved_by = v_user_id
        and sml.movement_type in ('initial', 'transfer_in', 'adjustment')
        and sml.moved_at >= v_day_start
        and sml.moved_at < v_day_end
      order by sml.moved_at desc
    ),
    stock_validation_row as (
      select
        sv.id,
        sv.created_at
      from public.stock_validations sv
      where sv.promotor_id = v_user_id
        and sv.validation_date = v_target_date
      order by sv.created_at desc
      limit 1
    ),
    promotion_rows as (
      select
        pr.id,
        pr.platform
      from public.promotion_reports pr
      where pr.promotor_id = v_user_id
        and pr.created_at >= v_day_start
        and pr.created_at < v_day_end
      order by pr.created_at desc
    ),
    follower_rows as (
      select
        fr.id,
        fr.follower_count
      from public.follower_reports fr
      where fr.promotor_id = v_user_id
        and fr.created_at >= v_day_start
        and fr.created_at < v_day_end
      order by fr.created_at desc
    ),
    allbrand_row as (
      select
        abr.id,
        abr.created_at
      from public.allbrand_reports abr
      where abr.promotor_id = v_user_id
        and abr.report_date = v_target_date
      order by abr.created_at desc
      limit 1
    ),
    monthly_attendance as (
      select count(*)::integer as total
      from public.attendance a
      where a.user_id = v_user_id
        and a.attendance_date >= v_month_start
        and a.attendance_date < v_month_end
    ),
    monthly_sell_out as (
      select count(*)::integer as total
      from public.sales_sell_out s
      where s.promotor_id = v_user_id
        and s.deleted_at is null
        and s.transaction_date >= v_month_start
        and s.transaction_date < v_month_end
    ),
    monthly_validation as (
      select count(*)::integer as total
      from public.stock_validations sv
      where sv.promotor_id = v_user_id
        and sv.validation_date >= v_month_start
        and sv.validation_date < v_month_end
    ),
    monthly_follower as (
      select coalesce(sum(fr.follower_count), 0)::integer as total
      from public.follower_reports fr
      where fr.promotor_id = v_user_id
        and fr.created_at >= v_month_start::timestamp
        and fr.created_at < v_month_end::timestamp
    )
    select jsonb_build_object(
      'attendance_data', (
        select to_jsonb(ar)
        from attendance_row ar
      ),
      'clock_out_data', (
        select to_jsonb(cr)
        from clock_out_row cr
      ),
      'sell_out_data', coalesce((
        select jsonb_agg(to_jsonb(sr))
        from sell_out_rows sr
      ), '[]'::jsonb),
      'sell_out_void_requests', coalesce((
        select jsonb_agg(to_jsonb(vr))
        from latest_void_rows vr
      ), '[]'::jsonb),
      'stock_input_data', coalesce((
        select jsonb_agg(to_jsonb(si))
        from stock_input_rows si
      ), '[]'::jsonb),
      'stock_validation_data', (
        select to_jsonb(sv)
        from stock_validation_row sv
      ),
      'promotion_data', coalesce((
        select jsonb_agg(to_jsonb(pr))
        from promotion_rows pr
      ), '[]'::jsonb),
      'follower_data', coalesce((
        select jsonb_agg(to_jsonb(fr))
        from follower_rows fr
      ), '[]'::jsonb),
      'all_brand_data', (
        select to_jsonb(ab)
        from allbrand_row ab
      ),
      'monthly_attendance_count', coalesce((
        select ma.total
        from monthly_attendance ma
      ), 0),
      'monthly_sell_out_count', coalesce((
        select ms.total
        from monthly_sell_out ms
      ), 0),
      'monthly_validation_count', coalesce((
        select mv.total
        from monthly_validation mv
      ), 0),
      'monthly_follower_increase', coalesce((
        select mf.total
        from monthly_follower mf
      ), 0)
    )
  );
end;
$$;

grant execute on function public.get_promotor_activity_snapshot(date) to authenticated;
