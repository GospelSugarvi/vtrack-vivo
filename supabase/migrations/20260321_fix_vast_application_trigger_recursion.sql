create or replace function public.vast_refresh_duplicate_count(p_application_id uuid)
returns void
language plpgsql
as $$
declare
  v_duplicate_count integer;
begin
  select count(*)::integer
    into v_duplicate_count
  from public.vast_fraud_signals
  where application_id = p_application_id
    and status = 'open';

  update public.vast_applications
  set duplicate_signal_count = v_duplicate_count
  where id = p_application_id
    and coalesce(duplicate_signal_count, 0) is distinct from v_duplicate_count;
end;
$$;

create or replace function public.vast_after_application_upsert()
returns trigger
language plpgsql
as $$
begin
  if pg_trigger_depth() > 1 then
    return new;
  end if;

  perform public.vast_detect_application_metadata_signals(new.id);
  return new;
end;
$$;

drop trigger if exists vast_after_application_upsert on public.vast_applications;
create trigger vast_after_application_upsert
after insert or update of customer_name, customer_phone, tenor_months, limit_amount, application_date, deleted_at
on public.vast_applications
for each row execute function public.vast_after_application_upsert();
