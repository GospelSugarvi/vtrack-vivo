create or replace function public.get_user_chat_rooms(p_user_id uuid)
returns table (
    room_id uuid,
    room_type varchar(20),
    room_name varchar(255),
    room_description text,
    store_id uuid,
    sator_id uuid,
    user1_id uuid,
    user2_id uuid,
    is_muted boolean,
    last_read_at timestamp with time zone,
    unread_count bigint,
    mention_unread_count bigint,
    mention_all_unread_count bigint,
    last_message_content text,
    last_message_time timestamp with time zone,
    last_message_sender_name varchar(255),
    member_count bigint,
    created_at timestamp with time zone
)
language plpgsql
security definer
set search_path = public
as $$
begin
    return query
    select
        cr.id as room_id,
        cr.room_type,
        cr.name as room_name,
        cr.description as room_description,
        cr.store_id,
        cr.sator_id,
        cr.user1_id,
        cr.user2_id,
        cm.is_muted,
        cm.last_read_at,
        coalesce((
            select count(*)
            from public.chat_messages msg
            where msg.room_id = cr.id
              and msg.created_at > coalesce(cm.last_read_at, '1970-01-01'::timestamp with time zone)
              and msg.is_deleted = false
              and msg.sender_id <> p_user_id
        ), 0) as unread_count,
        coalesce((
            select count(*)
            from public.app_notifications an
            where an.recipient_user_id = p_user_id
              and an.status = 'unread'
              and an.archived_at is null
              and an.category = 'chat'
              and an.type = 'chat_mention'
              and coalesce(an.payload ->> 'room_id', '') = cr.id::text
        ), 0) as mention_unread_count,
        coalesce((
            select count(*)
            from public.app_notifications an
            where an.recipient_user_id = p_user_id
              and an.status = 'unread'
              and an.archived_at is null
              and an.category = 'chat'
              and an.type = 'chat_mention_all'
              and coalesce(an.payload ->> 'room_id', '') = cr.id::text
        ), 0) as mention_all_unread_count,
        (
            select content
            from public.chat_messages msg
            where msg.room_id = cr.id
              and msg.is_deleted = false
            order by msg.created_at desc
            limit 1
        ) as last_message_content,
        (
            select created_at
            from public.chat_messages msg
            where msg.room_id = cr.id
              and msg.is_deleted = false
            order by msg.created_at desc
            limit 1
        ) as last_message_time,
        (
            select u.full_name
            from public.chat_messages msg
            join public.users u on u.id = msg.sender_id
            where msg.room_id = cr.id
              and msg.is_deleted = false
            order by msg.created_at desc
            limit 1
        ) as last_message_sender_name,
        (
            select count(*)
            from public.chat_members mem
            where mem.room_id = cr.id
              and mem.left_at is null
        ) as member_count,
        cr.created_at
    from public.chat_rooms cr
    join public.chat_members cm on cm.room_id = cr.id
    where cm.user_id = p_user_id
      and cm.left_at is null
      and cr.is_active = true
    order by
        case when unread_count > 0 then 0 else 1 end,
        last_message_time desc nulls last,
        cr.created_at desc;
end;
$$;

create or replace function public.send_message(
    p_room_id uuid,
    p_sender_id uuid,
    p_message_type varchar(20) default 'text',
    p_content text default null,
    p_image_url text default null,
    p_image_width integer default null,
    p_image_height integer default null,
    p_mentions uuid[] default null,
    p_reply_to_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
    v_message_id uuid;
    v_room_type varchar(20);
    v_room_name text := 'Chat';
    v_sender_name text := 'Seseorang';
    v_mentioned_user uuid;
    v_mentioned_role text;
    v_route text;
    v_snippet text;
    v_notification_type text := 'chat_mention';
begin
    if not is_room_member(p_room_id, p_sender_id) then
        raise exception 'User is not a member of this room';
    end if;

    select room_type, coalesce(name, 'Chat')
    into v_room_type, v_room_name
    from public.chat_rooms
    where id = p_room_id;

    if v_room_type = 'announcement' then
        if not exists (
            select 1 from public.users
            where id = p_sender_id
              and role in ('spv', 'admin')
        ) then
            raise exception 'Only SPV and Admin can post in announcement rooms';
        end if;
    end if;

    if p_message_type = 'text' and (p_content is null or length(trim(p_content)) = 0) then
        raise exception 'Text messages must have content';
    end if;

    if p_message_type = 'image' and p_image_url is null then
        raise exception 'Image messages must have image_url';
    end if;

    if p_mentions is not null then
        foreach v_mentioned_user in array p_mentions
        loop
            if not is_room_member(p_room_id, v_mentioned_user) then
                raise exception 'Cannot mention user who is not a room member: %', v_mentioned_user;
            end if;
        end loop;
    end if;

    insert into public.chat_messages (
        room_id,
        sender_id,
        message_type,
        content,
        image_url,
        image_width,
        image_height,
        mentions,
        reply_to_id
    ) values (
        p_room_id,
        p_sender_id,
        p_message_type,
        p_content,
        p_image_url,
        p_image_width,
        p_image_height,
        p_mentions,
        p_reply_to_id
    ) returning id into v_message_id;

    update public.chat_rooms
    set updated_at = now()
    where id = p_room_id;

    update public.chat_members
    set last_read_at = now()
    where room_id = p_room_id
      and user_id = p_sender_id;

    if p_mentions is not null and array_length(p_mentions, 1) > 0 then
        select coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'Seseorang'))
        into v_sender_name
        from public.users u
        where u.id = p_sender_id;

        if position('@all' in lower(coalesce(p_content, ''))) > 0 then
            v_notification_type := 'chat_mention_all';
        end if;

        v_snippet := case
            when p_message_type = 'image' then 'mengirim gambar dan mention Anda'
            when p_content is null or trim(p_content) = '' then 'mention Anda di chat'
            when length(trim(p_content)) > 90 then left(trim(p_content), 90) || '...'
            else trim(p_content)
        end;

        foreach v_mentioned_user in array p_mentions
        loop
            if v_mentioned_user = p_sender_id then
                continue;
            end if;

            select lower(coalesce(role::text, 'promotor'))
            into v_mentioned_role
            from public.users
            where id = v_mentioned_user;

            v_route := '/chat-room/' || p_room_id::text;

            perform public.create_app_notification(
                p_recipient_user_id := v_mentioned_user,
                p_actor_user_id := p_sender_id,
                p_role_target := coalesce(v_mentioned_role, 'promotor'),
                p_category := 'chat',
                p_type := v_notification_type,
                p_title := case
                    when v_notification_type = 'chat_mention_all'
                        then coalesce(v_sender_name, 'Seseorang') || ' mention @all'
                    else coalesce(v_sender_name, 'Seseorang') || ' mention Anda'
                end,
                p_body := coalesce(v_room_name, 'Chat') || ' · ' || coalesce(v_snippet, 'mention baru'),
                p_entity_type := 'chat_message',
                p_entity_id := v_message_id::text,
                p_action_route := v_route,
                p_action_params := jsonb_build_object(
                    'room_id', p_room_id,
                    'message_id', v_message_id
                ),
                p_payload := jsonb_build_object(
                    'room_id', p_room_id,
                    'room_name', v_room_name,
                    'message_id', v_message_id,
                    'sender_id', p_sender_id,
                    'sender_name', v_sender_name,
                    'mention_type', v_notification_type
                ),
                p_priority := 'high',
                p_dedupe_key := v_notification_type || ':' || v_message_id::text || ':' || v_mentioned_user::text
            );
        end loop;
    end if;

    return v_message_id;
end;
$$;
