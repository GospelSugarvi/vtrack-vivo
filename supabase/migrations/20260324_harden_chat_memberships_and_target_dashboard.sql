drop policy if exists "System can manage memberships" on public.chat_room_members;

create or replace function public.get_chat_room_members(
  p_room_id uuid,
  p_user_id uuid
)
returns table(id uuid, full_name text, nickname text, role text)
language plpgsql
security definer
set search_path = public
as $function$
begin
  if not exists (
    select 1
    from public.chat_members cm
    where cm.room_id = p_room_id
      and cm.user_id = p_user_id
      and cm.left_at is null
  ) then
    raise exception 'User is not a member of this room';
  end if;

  return query
  select
    u.id,
    u.full_name::text,
    u.nickname::text,
    u.role::text
  from public.chat_members cm
  join public.users u on u.id = cm.user_id
  where cm.room_id = p_room_id
    and cm.left_at is null
    and coalesce(u.status, 'active') = 'active'
  order by coalesce(nullif(u.nickname, ''), u.full_name), u.full_name;
end;
$function$;

revoke all on public.v_target_dashboard from public;
revoke all on public.v_target_dashboard from anon;
revoke all on public.v_target_dashboard from authenticated;
