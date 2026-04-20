create table if not exists public.permission_requests (
  id uuid primary key default gen_random_uuid(),
  promotor_id uuid not null references public.users(id) on delete cascade,
  sator_id uuid not null references public.users(id),
  spv_id uuid not null references public.users(id),
  request_date date not null,
  request_type text not null check (request_type in ('sick', 'personal', 'other')),
  reason text not null,
  note text,
  photo_url text,
  status text not null default 'pending_sator' check (
    status in (
      'pending_sator',
      'approved_sator',
      'rejected_sator',
      'approved_spv',
      'rejected_spv'
    )
  ),
  sator_comment text,
  sator_approved_by uuid references public.users(id),
  sator_approved_at timestamptz,
  spv_comment text,
  spv_approved_by uuid references public.users(id),
  spv_approved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint permission_requests_one_per_day unique (promotor_id, request_date)
);

create index if not exists idx_permission_requests_promotor_date
on public.permission_requests (promotor_id, request_date desc);

create index if not exists idx_permission_requests_sator_status
on public.permission_requests (sator_id, status, created_at desc);

create index if not exists idx_permission_requests_spv_status
on public.permission_requests (spv_id, status, created_at desc);

create or replace function public.permission_requests_set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trigger_permission_requests_set_updated_at on public.permission_requests;
create trigger trigger_permission_requests_set_updated_at
before update on public.permission_requests
for each row
execute function public.permission_requests_set_updated_at();

alter table public.permission_requests enable row level security;

drop policy if exists "permission_requests_promotor_select" on public.permission_requests;
create policy "permission_requests_promotor_select"
on public.permission_requests
for select
using (auth.uid() = promotor_id);

drop policy if exists "permission_requests_promotor_insert" on public.permission_requests;
create policy "permission_requests_promotor_insert"
on public.permission_requests
for insert
with check (
  auth.uid() = promotor_id
  and exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'promotor'
  )
);

drop policy if exists "permission_requests_sator_select" on public.permission_requests;
create policy "permission_requests_sator_select"
on public.permission_requests
for select
using (
  auth.uid() = sator_id
  and exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'sator'
  )
);

drop policy if exists "permission_requests_sator_update" on public.permission_requests;
create policy "permission_requests_sator_update"
on public.permission_requests
for update
using (
  auth.uid() = sator_id
  and exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'sator'
  )
)
with check (
  auth.uid() = sator_id
  and exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'sator'
  )
);

drop policy if exists "permission_requests_spv_select" on public.permission_requests;
create policy "permission_requests_spv_select"
on public.permission_requests
for select
using (
  auth.uid() = spv_id
  and exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'spv'
  )
);

drop policy if exists "permission_requests_spv_update" on public.permission_requests;
create policy "permission_requests_spv_update"
on public.permission_requests
for update
using (
  auth.uid() = spv_id
  and exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'spv'
  )
)
with check (
  auth.uid() = spv_id
  and exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'spv'
  )
);

drop policy if exists "permission_requests_admin_all" on public.permission_requests;
create policy "permission_requests_admin_all"
on public.permission_requests
for all
using (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'admin'
  )
)
with check (
  exists (
    select 1
    from public.users u
    where u.id = auth.uid()
      and u.role = 'admin'
  )
);

create or replace function public.submit_permission_request(
  p_request_date date,
  p_request_type text,
  p_reason text,
  p_note text default null,
  p_photo_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_promotor_id uuid := auth.uid();
  v_role text;
  v_sator_id uuid;
  v_spv_id uuid;
  v_request_id uuid;
begin
  if v_promotor_id is null then
    return jsonb_build_object('success', false, 'message', 'Sesi login tidak ditemukan.');
  end if;

  select u.role into v_role
  from public.users u
  where u.id = v_promotor_id;

  if coalesce(v_role, '') <> 'promotor' then
    return jsonb_build_object('success', false, 'message', 'Hanya promotor yang dapat membuat izin.');
  end if;

  if p_request_type not in ('sick', 'personal', 'other') then
    return jsonb_build_object('success', false, 'message', 'Jenis izin tidak valid.');
  end if;

  select hsp.sator_id
  into v_sator_id
  from public.hierarchy_sator_promotor hsp
  where hsp.promotor_id = v_promotor_id
    and hsp.active = true
  order by hsp.created_at desc nulls last
  limit 1;

  if v_sator_id is null then
    return jsonb_build_object('success', false, 'message', 'Sator untuk promotor ini belum terpasang.');
  end if;

  select hss.spv_id
  into v_spv_id
  from public.hierarchy_spv_sator hss
  where hss.sator_id = v_sator_id
    and hss.active = true
  order by hss.created_at desc nulls last
  limit 1;

  if v_spv_id is null then
    return jsonb_build_object('success', false, 'message', 'SPV untuk sator ini belum terpasang.');
  end if;

  insert into public.permission_requests (
    promotor_id,
    sator_id,
    spv_id,
    request_date,
    request_type,
    reason,
    note,
    photo_url
  ) values (
    v_promotor_id,
    v_sator_id,
    v_spv_id,
    p_request_date,
    p_request_type,
    trim(p_reason),
    nullif(trim(coalesce(p_note, '')), ''),
    nullif(trim(coalesce(p_photo_url, '')), '')
  )
  returning id into v_request_id;

  return jsonb_build_object(
    'success', true,
    'request_id', v_request_id,
    'message', 'Izin berhasil dikirim ke SATOR.'
  );
exception
  when unique_violation then
    return jsonb_build_object(
      'success', false,
      'message', 'Izin untuk tanggal tersebut sudah pernah dikirim.'
    );
end;
$$;

create or replace function public.process_permission_request_by_sator(
  p_request_id uuid,
  p_action text,
  p_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_request public.permission_requests%rowtype;
  v_role text;
  v_new_status text;
begin
  if v_actor_id is null then
    return jsonb_build_object('success', false, 'message', 'Sesi login tidak ditemukan.');
  end if;

  select role into v_role
  from public.users
  where id = v_actor_id;

  if coalesce(v_role, '') <> 'sator' then
    return jsonb_build_object('success', false, 'message', 'Hanya sator yang dapat memproses tahap ini.');
  end if;

  select *
  into v_request
  from public.permission_requests
  where id = p_request_id;

  if not found then
    return jsonb_build_object('success', false, 'message', 'Data izin tidak ditemukan.');
  end if;

  if v_request.sator_id <> v_actor_id then
    return jsonb_build_object('success', false, 'message', 'Izin ini bukan milik tim Anda.');
  end if;

  if v_request.status <> 'pending_sator' then
    return jsonb_build_object('success', false, 'message', 'Tahap SATOR sudah diproses.');
  end if;

  if p_action not in ('approve', 'reject') then
    return jsonb_build_object('success', false, 'message', 'Aksi tidak valid.');
  end if;

  v_new_status := case when p_action = 'approve' then 'approved_sator' else 'rejected_sator' end;

  update public.permission_requests
  set status = v_new_status,
      sator_comment = nullif(trim(coalesce(p_comment, '')), ''),
      sator_approved_by = v_actor_id,
      sator_approved_at = now()
  where id = p_request_id;

  return jsonb_build_object(
    'success', true,
    'status', v_new_status,
    'message', case when p_action = 'approve'
      then 'Izin diteruskan ke SPV.'
      else 'Izin ditolak oleh SATOR.'
    end
  );
end;
$$;

create or replace function public.process_permission_request_by_spv(
  p_request_id uuid,
  p_action text,
  p_comment text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_request public.permission_requests%rowtype;
  v_role text;
  v_new_status text;
begin
  if v_actor_id is null then
    return jsonb_build_object('success', false, 'message', 'Sesi login tidak ditemukan.');
  end if;

  select role into v_role
  from public.users
  where id = v_actor_id;

  if coalesce(v_role, '') <> 'spv' then
    return jsonb_build_object('success', false, 'message', 'Hanya SPV yang dapat memproses tahap ini.');
  end if;

  select *
  into v_request
  from public.permission_requests
  where id = p_request_id;

  if not found then
    return jsonb_build_object('success', false, 'message', 'Data izin tidak ditemukan.');
  end if;

  if v_request.spv_id <> v_actor_id then
    return jsonb_build_object('success', false, 'message', 'Izin ini bukan cakupan SPV Anda.');
  end if;

  if v_request.status <> 'approved_sator' then
    return jsonb_build_object('success', false, 'message', 'SPV hanya dapat memproses izin yang sudah disetujui SATOR.');
  end if;

  if p_action not in ('approve', 'reject') then
    return jsonb_build_object('success', false, 'message', 'Aksi tidak valid.');
  end if;

  v_new_status := case when p_action = 'approve' then 'approved_spv' else 'rejected_spv' end;

  update public.permission_requests
  set status = v_new_status,
      spv_comment = nullif(trim(coalesce(p_comment, '')), ''),
      spv_approved_by = v_actor_id,
      spv_approved_at = now()
  where id = p_request_id;

  return jsonb_build_object(
    'success', true,
    'status', v_new_status,
    'message', case when p_action = 'approve'
      then 'Izin disetujui SPV.'
      else 'Izin ditolak oleh SPV.'
    end
  );
end;
$$;

comment on table public.permission_requests is 'Pengajuan izin promotor dengan approval bertingkat dari sator lalu spv.';
comment on function public.submit_permission_request(date, text, text, text, text) is 'Promotor mengajukan izin harian.';
comment on function public.process_permission_request_by_sator(uuid, text, text) is 'Tahap approval izin oleh sator.';
comment on function public.process_permission_request_by_spv(uuid, text, text) is 'Tahap approval izin oleh spv setelah sator approve.';
