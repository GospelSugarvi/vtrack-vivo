update public.ai_feature_settings
set
  system_prompt = trim($prompt$
Kamu adalah rekan tim penjualan yang hangat, santai, dan enak diajak ngobrol.
Tugasmu menulis komentar singkat di live feed supaya promotor merasa diperhatiin, diapresiasi, dan tetap semangat.

Aturan:
- Tulis seperti teman satu tim yang peka konteks, bukan announcer resmi.
- Bahasa harus natural, ringan, dan tidak kaku.
- Boleh pakai sapaan "Kak" kalau cocok dengan konteks, tapi jangan dipaksakan di setiap kalimat.
- Ambil detail yang paling relevan dari konteks, lalu ubah jadi komentar yang terasa hidup.
- Hindari kalimat generik yang bisa ditempel ke semua postingan.
- Hindari frasa kaku seperti "berdasarkan data", "informasi menunjukkan", atau "selamat atas pencapaian tersebut".
- Jangan menggurui, jangan terlalu formal, dan jangan terlalu heboh.
- Jangan pernah menyebut diri sebagai AI, bot, sistem, atau model.
- Maksimal 1 kalimat utama atau 2 kalimat sangat singkat kalau memang perlu.
- Emoji tidak wajib. Kalau dipakai, cukup satu dan harus terasa natural.
- Jangan menyebut data yang tidak ada di konteks.

Keluarkan hanya isi komentar akhirnya.
$prompt$),
  config_json = jsonb_set(
    jsonb_set(
      jsonb_set(
        jsonb_set(
          jsonb_set(
            coalesce(config_json, '{}'::jsonb),
            '{delay_seconds}',
            to_jsonb(greatest(coalesce(nullif(config_json ->> 'delay_seconds', '')::integer, 25), 25)),
            true
          ),
          '{enable_reply_threads}',
          'true'::jsonb,
          true
        ),
        '{min_output_chars}',
        to_jsonb(greatest(coalesce(nullif(config_json ->> 'min_output_chars', '')::integer, 28), 20)),
        true
      ),
      '{max_output_chars}',
      to_jsonb(greatest(coalesce(nullif(config_json ->> 'max_output_chars', '')::integer, 160), 120)),
      true
    ),
    '{temperature}',
    to_jsonb(coalesce(nullif(config_json ->> 'temperature', '')::numeric, 0.9)),
    true
  ),
  updated_at = now()
where feature_key = 'live_feed_sales_comment';

create or replace function public.enqueue_live_feed_ai_comment_reply_job()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_enabled boolean := false;
  v_enable_reply_threads boolean := true;
  v_system_persona_id uuid;
  v_persona_user_id uuid;
  v_parent_user_id uuid;
  v_should_enqueue boolean := false;
begin
  if new.deleted_at is not null then
    return new;
  end if;

  select afs.enabled,
         coalesce((afs.config_json ->> 'enable_reply_threads')::boolean, true),
         nullif(afs.config_json ->> 'system_persona_id', '')::uuid,
         nullif(afs.config_json ->> 'persona_user_id', '')::uuid
    into v_enabled, v_enable_reply_threads, v_system_persona_id, v_persona_user_id
  from public.ai_feature_settings afs
  where afs.feature_key = 'live_feed_sales_comment'
  limit 1;

  if coalesce(v_enabled, false) = false
     or coalesce(v_enable_reply_threads, true) = false then
    return new;
  end if;

  if v_system_persona_id is not null then
    select sp.linked_user_id
      into v_persona_user_id
    from public.system_personas sp
    where sp.id = v_system_persona_id
      and sp.is_active = true
    limit 1;
  end if;

  if v_persona_user_id is null then
    return new;
  end if;

  if new.user_id = v_persona_user_id then
    return new;
  end if;

  if v_persona_user_id = any(coalesce(new.mentioned_user_ids, '{}'::uuid[])) then
    v_should_enqueue := true;
  end if;

  if new.parent_comment_id is not null then
    select fc.user_id
      into v_parent_user_id
    from public.feed_comments fc
    where fc.id = new.parent_comment_id
      and fc.deleted_at is null
    limit 1;

    if v_parent_user_id = v_persona_user_id then
      v_should_enqueue := true;
    end if;
  end if;

  if v_should_enqueue then
    insert into public.ai_feed_comment_reply_jobs (
      sale_id,
      source_comment_id,
      persona_user_id
    )
    values (
      new.sale_id,
      new.id,
      v_persona_user_id
    )
    on conflict (source_comment_id) do nothing;

    perform public.dispatch_live_feed_ai_sales_comment_worker(1);
  end if;

  return new;
end;
$$;

update public.ai_feed_comment_reply_jobs
set
  status = 'pending',
  last_error = null,
  processed_at = null,
  updated_at = now()
where status = 'skipped'
  and last_error = 'Reply persona dimatikan: mode komentar satu arah.';

select public.dispatch_live_feed_ai_sales_comment_worker(5)
from public.ai_feed_comment_reply_jobs
where status = 'pending'
limit 1;
