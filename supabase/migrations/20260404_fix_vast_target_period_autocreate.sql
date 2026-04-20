create or replace function public.get_or_create_target_period(
    p_month integer,
    p_year integer
)
returns uuid
language plpgsql
set search_path = public
as $$
declare
    v_period_id uuid;
    v_existing_active_id uuid;
    v_start_date date;
    v_end_date date;
    v_period_name text;
    v_status text;
    v_month_names text[] := array[
        'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
        'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
begin
    select tp.id
      into v_period_id
    from public.target_periods tp
    where tp.target_month = p_month
      and tp.target_year = p_year
      and tp.deleted_at is null
    order by tp.created_at desc
    limit 1;

    if v_period_id is not null then
        return v_period_id;
    end if;

    select tp.id
      into v_existing_active_id
    from public.target_periods tp
    where tp.status = 'active'
      and tp.deleted_at is null
    order by
      tp.target_year desc nulls last,
      tp.target_month desc nulls last,
      tp.start_date desc nulls last,
      tp.created_at desc
    limit 1;

    v_start_date := make_date(p_year, p_month, 1);
    v_end_date := (v_start_date + interval '1 month' - interval '1 day')::date;
    v_period_name := v_month_names[p_month] || ' ' || p_year;
    v_status := case
      when v_existing_active_id is null then 'active'
      else 'inactive'
    end;

    insert into public.target_periods (
      period_name,
      start_date,
      end_date,
      target_month,
      target_year,
      status
    )
    values (
      v_period_name,
      v_start_date,
      v_end_date,
      p_month,
      p_year,
      v_status
    )
    returning id into v_period_id;

    return v_period_id;
end;
$$;

grant execute on function public.get_or_create_target_period(integer, integer)
to authenticated;
