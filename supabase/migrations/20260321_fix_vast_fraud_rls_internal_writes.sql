set check_function_bodies = off;

create or replace function public.vast_create_alerts_for_signal(p_signal_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_signal record;
begin
  select fs.*, va.sator_id, va.spv_id, va.customer_name, va.application_date
    into v_signal
  from public.vast_fraud_signals fs
  join public.vast_applications va on va.id = fs.application_id
  where fs.id = p_signal_id;

  if not found then
    return;
  end if;

  if v_signal.sator_id is not null then
    insert into public.vast_alerts (
      signal_id, application_id, recipient_user_id, recipient_role, title, body
    ) values (
      v_signal.id,
      v_signal.application_id,
      v_signal.sator_id,
      'sator',
      'Indikasi duplikasi bukti VAST',
      v_signal.summary
    )
    on conflict (signal_id, recipient_user_id) do nothing;
  end if;

  if v_signal.spv_id is not null then
    insert into public.vast_alerts (
      signal_id, application_id, recipient_user_id, recipient_role, title, body
    ) values (
      v_signal.id,
      v_signal.application_id,
      v_signal.spv_id,
      'spv',
      'Indikasi duplikasi bukti VAST',
      v_signal.summary
    )
    on conflict (signal_id, recipient_user_id) do nothing;
  end if;
end;
$function$;

create or replace function public.vast_detect_evidence_signals(p_application_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_match record;
  v_signal_id uuid;
begin
  for v_match in
    select
      current_ev.id as current_evidence_id,
      matched_ev.id as matched_evidence_id,
      matched_app.id as matched_application_id,
      current_ev.sha256_hex,
      current_ev.perceptual_hash,
      matched_app.application_date as matched_application_date,
      current_app.application_date as current_application_date,
      case
        when current_ev.sha256_hex is not null and current_ev.sha256_hex = matched_ev.sha256_hex then 'exact_file_match'
        when current_ev.perceptual_hash is not null and current_ev.perceptual_hash = matched_ev.perceptual_hash then 'perceptual_match'
      end as signal_type
    from public.vast_application_evidences current_ev
    join public.vast_applications current_app on current_app.id = current_ev.application_id
    join public.vast_application_evidences matched_ev
      on matched_ev.id <> current_ev.id
     and (
       (current_ev.sha256_hex is not null and current_ev.sha256_hex = matched_ev.sha256_hex)
       or (current_ev.perceptual_hash is not null and current_ev.perceptual_hash = matched_ev.perceptual_hash)
     )
    join public.vast_applications matched_app on matched_app.id = matched_ev.application_id
    where current_ev.application_id = p_application_id
      and matched_app.id <> current_app.id
      and matched_app.deleted_at is null
  loop
    insert into public.vast_fraud_signals (
      application_id, matched_application_id, signal_type, severity, summary, detection_payload
    ) values (
      p_application_id,
      v_match.matched_application_id,
      v_match.signal_type,
      case when v_match.signal_type = 'exact_file_match' then 'high' else 'medium' end,
      'Bukti foto pernah dikirim pada ' || to_char(v_match.matched_application_date, 'DD Mon YYYY') ||
      ' dan dipakai lagi pada ' || to_char(v_match.current_application_date, 'DD Mon YYYY') || '.',
      jsonb_build_object(
        'old_application_date', v_match.matched_application_date,
        'new_application_date', v_match.current_application_date,
        'matched_application_id', v_match.matched_application_id,
        'signal_type', v_match.signal_type
      )
    )
    on conflict (application_id, matched_application_id, signal_type)
    do update set
      detection_payload = excluded.detection_payload,
      updated_at = now()
    returning id into v_signal_id;

    if v_signal_id is not null then
      insert into public.vast_fraud_signal_items (
        signal_id, current_evidence_id, matched_evidence_id, match_type, confidence_score, details
      ) values (
        v_signal_id, v_match.current_evidence_id, v_match.matched_evidence_id,
        case when v_match.signal_type = 'exact_file_match' then 'exact_hash' else 'perceptual_hash' end,
        case when v_match.signal_type = 'exact_file_match' then 1 else 0.92 end,
        jsonb_build_object(
          'old_application_date', v_match.matched_application_date,
          'new_application_date', v_match.current_application_date
        )
      );

      perform public.vast_create_alerts_for_signal(v_signal_id);
    end if;
  end loop;

  perform public.vast_refresh_duplicate_count(p_application_id);
end;
$function$;

create or replace function public.vast_after_evidence_upsert()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  perform public.vast_detect_evidence_signals(new.application_id);
  return new;
end;
$function$;

drop policy if exists "vast fraud signals internal write" on public.vast_fraud_signals;
create policy "vast fraud signals internal write"
on public.vast_fraud_signals
for all
to public
using (current_user = 'postgres')
with check (current_user = 'postgres');

drop policy if exists "vast fraud signal items internal write" on public.vast_fraud_signal_items;
create policy "vast fraud signal items internal write"
on public.vast_fraud_signal_items
for all
to public
using (current_user = 'postgres')
with check (current_user = 'postgres');

drop policy if exists "vast alerts internal write" on public.vast_alerts;
create policy "vast alerts internal write"
on public.vast_alerts
for all
to public
using (current_user = 'postgres')
with check (current_user = 'postgres');
