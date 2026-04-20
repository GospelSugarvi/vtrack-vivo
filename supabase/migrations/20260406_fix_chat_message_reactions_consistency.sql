create or replace function public.get_message_reactions_json(
  p_message_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return coalesce((
    select jsonb_object_agg(
      reaction_row.emoji,
      jsonb_build_object(
        'count', reaction_row.reaction_count,
        'users', reaction_row.users
      )
    )
    from (
      select
        mr.emoji,
        count(*)::int as reaction_count,
        jsonb_agg(
          jsonb_build_object(
            'user_id', mr.user_id,
            'name', coalesce(nullif(trim(u.nickname), ''), u.full_name, 'User')
          )
          order by mr.created_at asc
        ) as users
      from public.message_reactions mr
      join public.users u on u.id = mr.user_id
      where mr.message_id = p_message_id
      group by mr.emoji
    ) as reaction_row
  ), '{}'::jsonb);
end;
$$;

grant execute on function public.get_message_reactions_json(uuid) to authenticated;

create or replace function public.set_message_reaction(
  p_message_id uuid,
  p_emoji text,
  p_active boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor_id uuid := auth.uid();
  v_room_id uuid;
begin
  if v_actor_id is null then
    raise exception 'Authentication required';
  end if;

  select msg.room_id
  into v_room_id
  from public.chat_messages msg
  where msg.id = p_message_id
    and msg.is_deleted = false;

  if v_room_id is null then
    raise exception 'Message not found';
  end if;

  if not exists (
    select 1
    from public.chat_members cm
    where cm.room_id = v_room_id
      and cm.user_id = v_actor_id
      and cm.left_at is null
  ) then
    raise exception 'User is not a member of this room';
  end if;

  if coalesce(trim(p_emoji), '') = '' then
    raise exception 'Emoji is required';
  end if;

  if p_active then
    insert into public.message_reactions (message_id, user_id, emoji)
    values (p_message_id, v_actor_id, left(trim(p_emoji), 10))
    on conflict (message_id, user_id, emoji) do nothing;
  else
    delete from public.message_reactions
    where message_id = p_message_id
      and user_id = v_actor_id
      and emoji = left(trim(p_emoji), 10);
  end if;

  return public.get_message_reactions_json(p_message_id);
end;
$$;

grant execute on function public.set_message_reaction(uuid, text, boolean) to authenticated;

drop function if exists public.get_chat_messages(uuid, uuid, integer, integer);

create function public.get_chat_messages(
    p_room_id uuid,
    p_user_id uuid,
    p_limit integer default 50,
    p_offset integer default 0
)
returns table (
    message_id uuid,
    sender_id uuid,
    sender_name varchar(255),
    sender_role varchar(50),
    message_type varchar(20),
    content text,
    image_url text,
    image_width integer,
    image_height integer,
    mentions uuid[],
    reply_to_id uuid,
    reply_to_content text,
    reply_to_sender_name varchar(255),
    is_edited boolean,
    edited_at timestamp with time zone,
    created_at timestamp with time zone,
    read_by_count bigint,
    reactions jsonb,
    is_own_message boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
    if not public.is_room_member(p_room_id, p_user_id) then
        raise exception 'User is not a member of this room';
    end if;

    return query
    select
        msg.id as message_id,
        msg.sender_id,
        sender_user.full_name::varchar(255) as sender_name,
        sender_user.role::varchar(50) as sender_role,
        msg.message_type,
        msg.content,
        msg.image_url,
        msg.image_width,
        msg.image_height,
        msg.mentions,
        msg.reply_to_id,
        reply_msg.content as reply_to_content,
        reply_user.full_name::varchar(255) as reply_to_sender_name,
        msg.is_edited,
        msg.edited_at,
        msg.created_at,
        (
            select count(*)
            from public.message_reads mr
            where mr.message_id = msg.id
        ) as read_by_count,
        public.get_message_reactions_json(msg.id) as reactions,
        (msg.sender_id = p_user_id) as is_own_message
    from public.chat_messages msg
    left join public.users sender_user on sender_user.id = msg.sender_id
    left join public.chat_messages reply_msg on reply_msg.id = msg.reply_to_id
    left join public.users reply_user on reply_user.id = reply_msg.sender_id
    where msg.room_id = p_room_id
      and msg.is_deleted = false
    order by msg.created_at desc
    limit p_limit
    offset p_offset;
end;
$$;

grant execute on function public.get_chat_messages(uuid, uuid, integer, integer) to authenticated;
