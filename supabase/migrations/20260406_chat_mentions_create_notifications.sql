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
begin
    if not is_room_member(p_room_id, p_sender_id) then
        raise exception 'User is not a member of this room';
    end if;

    select room_type, coalesce(name, 'Chat')
    into v_room_type, v_room_name
    from chat_rooms
    where id = p_room_id;

    if v_room_type = 'announcement' then
        if not exists (
            select 1 from users
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

    insert into chat_messages (
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

    update chat_rooms
    set updated_at = now()
    where id = p_room_id;

    if p_mentions is not null and array_length(p_mentions, 1) > 0 then
        select coalesce(nullif(trim(u.nickname), ''), coalesce(u.full_name, 'Seseorang'))
        into v_sender_name
        from public.users u
        where u.id = p_sender_id;

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

            v_route := case v_mentioned_role
                when 'sator' then '/sator?tab=chat'
                when 'spv' then '/spv?tab=chat'
                else '/promotor?tab=chat'
            end;

            perform public.create_app_notification(
                p_recipient_user_id := v_mentioned_user,
                p_actor_user_id := p_sender_id,
                p_role_target := coalesce(v_mentioned_role, 'promotor'),
                p_category := 'chat',
                p_type := 'chat_mention',
                p_title := coalesce(v_sender_name, 'Seseorang') || ' mention Anda',
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
                    'sender_name', v_sender_name
                ),
                p_priority := 'high',
                p_dedupe_key := 'chat_mention:' || v_message_id::text || ':' || v_mentioned_user::text
            );
        end loop;
    end if;

    return v_message_id;
end;
$$;
