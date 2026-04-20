create or replace function public.sum_allbrand_brand_units(p_data jsonb)
returns integer
language sql
immutable
set search_path = public
as $$
  select coalesce(sum(
    coalesce(nullif(value ->> 'under_2m', '')::int, 0) +
    coalesce(nullif(value ->> '2m_4m', '')::int, 0) +
    coalesce(nullif(value ->> '4m_6m', '')::int, 0) +
    coalesce(nullif(value ->> 'above_6m', '')::int, 0)
  ), 0)::int
  from jsonb_each(case when jsonb_typeof(coalesce(p_data, '{}'::jsonb)) = 'object' then p_data else '{}'::jsonb end);
$$;

grant execute on function public.sum_allbrand_brand_units(jsonb) to authenticated;
