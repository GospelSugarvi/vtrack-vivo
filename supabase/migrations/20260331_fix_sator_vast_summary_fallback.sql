create or replace function public.get_sator_vast_page_snapshot(
  p_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_role text;
  v_today date := coalesce(p_date, current_date);
  v_month_key date := date_trunc('month', coalesce(p_date, current_date))::date;
  v_week_start date := (coalesce(p_date, current_date) - ((extract(isodow from coalesce(p_date, current_date))::int) - 1) * interval '1 day')::date;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select role into v_role
  from public.users
  where id = v_actor_id;

  if coalesce(v_role, '') <> 'sator' and not public.is_elevated_user() then
    raise exception 'Forbidden';
  end if;

  return (
    with profile as (
      select
        coalesce(u.full_name, 'SATOR') as full_name,
        coalesce(u.area, '-') as area
      from public.users u
      where u.id = v_actor_id
    ),
    active_period as (
      select tp.id
      from public.target_periods tp
      where tp.status = 'active'
        and tp.deleted_at is null
      order by tp.target_year desc, tp.target_month desc, tp.created_at desc
      limit 1
    ),
    promotor_scope as (
      select distinct
        p.id as promotor_id,
        coalesce(nullif(trim(p.nickname), ''), coalesce(p.full_name, 'Promotor')) as display_name,
        coalesce(p.full_name, 'Promotor') as full_name
      from public.hierarchy_sator_promotor hsp
      join public.users p on p.id = hsp.promotor_id
      where hsp.sator_id = v_actor_id
        and hsp.active = true
        and p.deleted_at is null
    ),
    latest_store as (
      select distinct on (aps.promotor_id)
        aps.promotor_id,
        coalesce(st.store_name, '-') as store_name
      from public.assignments_promotor_store aps
      left join public.stores st on st.id = aps.store_id
      where aps.active = true
        and aps.promotor_id in (select promotor_id from promotor_scope)
      order by aps.promotor_id, aps.created_at desc nulls last, aps.store_id
    ),
    targets as (
      select
        ut.user_id as promotor_id,
        coalesce(ut.target_vast, 0)::int as monthly_target
      from public.user_targets ut
      join active_period ap on ap.id = ut.period_id
      where ut.user_id in (select promotor_id from promotor_scope)
    ),
    daily as (
      select *
      from public.vast_agg_daily_promotor
      where promotor_id in (select promotor_id from promotor_scope)
        and metric_date = v_today
    ),
    weekly as (
      select *
      from public.vast_agg_weekly_promotor
      where promotor_id in (select promotor_id from promotor_scope)
        and week_start_date = v_week_start
    ),
    monthly as (
      select *
      from public.vast_agg_monthly_promotor
      where promotor_id in (select promotor_id from promotor_scope)
        and month_key = v_month_key
    ),
    daily_summary as (
      select jsonb_build_object(
        'target_submissions', coalesce(sum(
          case
            when coalesce(t.monthly_target, 0) <= 0 then 0
            else ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)::int
          end
        ), 0),
        'total_submissions', coalesce(sum(d.total_submissions), 0),
        'total_acc', coalesce(sum(d.total_acc), 0),
        'total_pending', coalesce(sum(d.total_pending), 0),
        'total_active_pending', coalesce(sum(d.total_active_pending), 0),
        'total_reject', coalesce(sum(d.total_reject), 0),
        'total_closed_direct', coalesce(sum(d.total_closed_direct), 0),
        'total_closed_follow_up', coalesce(sum(d.total_closed_follow_up), 0),
        'total_duplicate_alerts', coalesce(sum(d.total_duplicate_alerts), 0),
        'promotor_with_input', count(*) filter (where coalesce(d.total_submissions, 0) > 0),
        'achievement_pct', case
          when coalesce(sum(
            case
              when coalesce(t.monthly_target, 0) <= 0 then 0
              else ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)::int
            end
          ), 0) > 0
          then (
            coalesce(sum(d.total_submissions), 0)::numeric /
            sum(
              case
                when coalesce(t.monthly_target, 0) <= 0 then 0
                else ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)::int
              end
            )::numeric
          ) * 100
          else 0
        end,
        'underperform', case
          when coalesce(sum(
            case
              when coalesce(t.monthly_target, 0) <= 0 then 0
              else ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)::int
            end
          ), 0) <= 0 then false
          else coalesce(sum(d.total_submissions), 0) < sum(
            case
              when coalesce(t.monthly_target, 0) <= 0 then 0
              else ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)::int
            end
          )
        end
      ) as data
      from promotor_scope ps
      left join targets t on t.promotor_id = ps.promotor_id
      left join daily d on d.promotor_id = ps.promotor_id
    ),
    weekly_summary as (
      select jsonb_build_object(
        'target_submissions', coalesce(sum(
          (
            (coalesce(t.monthly_target, 0) / 4) +
            case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
          )::int
        ), 0),
        'total_submissions', coalesce(sum(w.total_submissions), 0),
        'total_acc', coalesce(sum(w.total_acc), 0),
        'total_pending', coalesce(sum(w.total_pending), 0),
        'total_active_pending', coalesce(sum(w.total_active_pending), 0),
        'total_reject', coalesce(sum(w.total_reject), 0),
        'total_closed_direct', coalesce(sum(w.total_closed_direct), 0),
        'total_closed_follow_up', coalesce(sum(w.total_closed_follow_up), 0),
        'total_duplicate_alerts', coalesce(sum(w.total_duplicate_alerts), 0),
        'promotor_with_input', count(*) filter (where coalesce(w.total_submissions, 0) > 0),
        'achievement_pct', case
          when coalesce(sum(
            (
              (coalesce(t.monthly_target, 0) / 4) +
              case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
            )::int
          ), 0) > 0
          then (coalesce(sum(w.total_submissions), 0)::numeric / sum(
            (
              (coalesce(t.monthly_target, 0) / 4) +
              case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
            )::int
          )::numeric) * 100
          else 0
        end,
        'underperform', case
          when coalesce(sum(
            (
              (coalesce(t.monthly_target, 0) / 4) +
              case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
            )::int
          ), 0) <= 0 then false
          else coalesce(sum(w.total_submissions), 0) < sum(
            (
              (coalesce(t.monthly_target, 0) / 4) +
              case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
            )::int
          )
        end
      ) as data
      from promotor_scope ps
      left join targets t on t.promotor_id = ps.promotor_id
      left join weekly w on w.promotor_id = ps.promotor_id
    ),
    monthly_summary as (
      select jsonb_build_object(
        'target_submissions', coalesce(sum(coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0)), 0),
        'total_submissions', coalesce(sum(m.total_submissions), 0),
        'total_acc', coalesce(sum(m.total_acc), 0),
        'total_pending', coalesce(sum(m.total_pending), 0),
        'total_active_pending', coalesce(sum(m.total_active_pending), 0),
        'total_reject', coalesce(sum(m.total_reject), 0),
        'total_closed_direct', coalesce(sum(m.total_closed_direct), 0),
        'total_closed_follow_up', coalesce(sum(m.total_closed_follow_up), 0),
        'total_duplicate_alerts', coalesce(sum(m.total_duplicate_alerts), 0),
        'promotor_with_input', count(*) filter (where coalesce(m.total_submissions, 0) > 0),
        'achievement_pct', case
          when coalesce(sum(coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0)), 0) > 0
          then (coalesce(sum(m.total_submissions), 0)::numeric / sum(coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0))::numeric) * 100
          else 0
        end,
        'underperform', case
          when coalesce(sum(coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0)), 0) <= 0 then false
          else coalesce(sum(m.total_submissions), 0) < sum(coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0))
        end
      ) as data
      from promotor_scope ps
      left join targets t on t.promotor_id = ps.promotor_id
      left join monthly m on m.promotor_id = ps.promotor_id
    ),
    rows_daily as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(t.monthly_target, 0),
          'target_vast', case
            when coalesce(t.monthly_target, 0) <= 0 then 0
            else ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)::int
          end,
          'period_submissions', coalesce(d.total_submissions, 0),
          'pending', coalesce(d.total_active_pending, 0),
          'duplicate_alerts', coalesce(d.total_duplicate_alerts, 0),
          'total_acc', coalesce(d.total_acc, 0),
          'total_reject', coalesce(d.total_reject, 0),
          'promotor_with_input', case when coalesce(d.total_submissions, 0) > 0 then 1 else 0 end,
          'achievement_pct', case
            when coalesce(t.monthly_target, 0) > 0
            then (coalesce(d.total_submissions, 0)::numeric / ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)) * 100
            else 0
          end,
          'underperform', case
            when coalesce(t.monthly_target, 0) <= 0 then false
            else coalesce(d.total_submissions, 0) < ceil(t.monthly_target::numeric / extract(day from (date_trunc('month', v_today) + interval '1 month - 1 day'))::numeric)
          end
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join targets t on t.promotor_id = ps.promotor_id
        left join daily d on d.promotor_id = ps.promotor_id
      ) q
    ),
    rows_weekly as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(t.monthly_target, 0),
          'target_vast',
            (
              (coalesce(t.monthly_target, 0) / 4) +
              case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
            )::int,
          'period_submissions', coalesce(w.total_submissions, 0),
          'pending', coalesce(w.total_active_pending, 0),
          'duplicate_alerts', coalesce(w.total_duplicate_alerts, 0),
          'total_acc', coalesce(w.total_acc, 0),
          'total_reject', coalesce(w.total_reject, 0),
          'promotor_with_input', case when coalesce(w.total_submissions, 0) > 0 then 1 else 0 end,
          'achievement_pct', case
            when coalesce(t.monthly_target, 0) > 0
            then (
              coalesce(w.total_submissions, 0)::numeric /
              greatest(
                (
                  (coalesce(t.monthly_target, 0) / 4) +
                  case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
                )::numeric,
                1
              )
            ) * 100
            else 0
          end,
          'underperform', case
            when coalesce(t.monthly_target, 0) <= 0 then false
            else coalesce(w.total_submissions, 0) <
              (
                (coalesce(t.monthly_target, 0) / 4) +
                case when ((extract(day from v_today)::int - 1) / 7) < (coalesce(t.monthly_target, 0) % 4) then 1 else 0 end
              )::int
          end
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join targets t on t.promotor_id = ps.promotor_id
        left join weekly w on w.promotor_id = ps.promotor_id
      ) q
    ),
    rows_monthly as (
      select coalesce(jsonb_agg(row_data order by (row_data ->> 'period_submissions')::int desc, row_data ->> 'name'), '[]'::jsonb) as data
      from (
        select jsonb_build_object(
          'id', ps.promotor_id,
          'name', ps.display_name,
          'store_name', coalesce(ls.store_name, '-'),
          'monthly_target', coalesce(t.monthly_target, 0),
          'target_vast', coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0),
          'period_submissions', coalesce(m.total_submissions, 0),
          'pending', coalesce(m.total_active_pending, 0),
          'duplicate_alerts', coalesce(m.total_duplicate_alerts, 0),
          'total_acc', coalesce(m.total_acc, 0),
          'total_reject', coalesce(m.total_reject, 0),
          'promotor_with_input', case when coalesce(m.total_submissions, 0) > 0 then 1 else 0 end,
          'achievement_pct', case
            when coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0) > 0
            then (coalesce(m.total_submissions, 0)::numeric / coalesce(nullif(m.target_submissions, 0), t.monthly_target)::numeric) * 100
            else coalesce(m.achievement_pct, 0)
          end,
          'underperform', coalesce(m.underperform, coalesce(m.total_submissions, 0) < coalesce(nullif(m.target_submissions, 0), t.monthly_target, 0))
        ) as row_data
        from promotor_scope ps
        left join latest_store ls on ls.promotor_id = ps.promotor_id
        left join targets t on t.promotor_id = ps.promotor_id
        left join monthly m on m.promotor_id = ps.promotor_id
      ) q
    ),
    alerts as (
      select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at desc), '[]'::jsonb) as data
      from (
        select id, signal_id, application_id, title, body, created_at, is_read
        from public.vast_alerts
        where recipient_user_id = v_actor_id
        order by created_at desc
        limit 50
      ) a
    )
    select jsonb_build_object(
      'profile', coalesce((select to_jsonb(profile) from profile), '{}'::jsonb),
      'daily', coalesce(
        (
          select to_jsonb(d)
          from public.vast_agg_daily_sator d
          where d.sator_id = v_actor_id
            and d.metric_date = v_today
            and (
              coalesce(d.target_submissions, 0) > 0 or
              coalesce(d.total_submissions, 0) > 0 or
              coalesce(d.total_acc, 0) > 0 or
              coalesce(d.total_active_pending, 0) > 0 or
              coalesce(d.total_reject, 0) > 0
            )
          limit 1
        ),
        coalesce((select data from daily_summary), '{}'::jsonb)
      ),
      'weekly', coalesce(
        (
          select to_jsonb(w)
          from public.vast_agg_weekly_sator w
          where w.sator_id = v_actor_id
            and w.week_start_date = v_week_start
            and (
              coalesce(w.target_submissions, 0) > 0 or
              coalesce(w.total_submissions, 0) > 0 or
              coalesce(w.total_acc, 0) > 0 or
              coalesce(w.total_active_pending, 0) > 0 or
              coalesce(w.total_reject, 0) > 0
            )
          limit 1
        ),
        coalesce((select data from weekly_summary), '{}'::jsonb)
      ),
      'monthly', coalesce(
        (
          select to_jsonb(m)
          from public.vast_agg_monthly_sator m
          where m.sator_id = v_actor_id
            and m.month_key = v_month_key
            and (
              coalesce(m.target_submissions, 0) > 0 or
              coalesce(m.total_submissions, 0) > 0 or
              coalesce(m.total_acc, 0) > 0 or
              coalesce(m.total_active_pending, 0) > 0 or
              coalesce(m.total_reject, 0) > 0
            )
          limit 1
        ),
        coalesce((select data from monthly_summary), '{}'::jsonb)
      ),
      'rows_daily', coalesce((select data from rows_daily), '[]'::jsonb),
      'rows_weekly', coalesce((select data from rows_weekly), '[]'::jsonb),
      'rows_monthly', coalesce((select data from rows_monthly), '[]'::jsonb),
      'alerts', coalesce((select data from alerts), '[]'::jsonb)
    )
  );
end;
$$;

grant execute on function public.get_sator_vast_page_snapshot(date) to authenticated;
