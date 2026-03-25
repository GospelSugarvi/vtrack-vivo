-- =============================================
-- AUTOMATIC CHAT MEMBERSHIP TRIGGERS
-- Date: 28 January 2026
-- Description: Syncs chat memberships with Admin assignments and hierarchy
-- =============================================

-- =============================================
-- 1. HELPER: Ensure Room and Membership
-- =============================================

-- Function to safely add member to a room
CREATE OR REPLACE FUNCTION public.sync_chat_member(p_room_id UUID, p_user_id UUID)
RETURNS VOID AS $$
BEGIN
    INSERT INTO public.chat_members (room_id, user_id)
    VALUES (p_room_id, p_user_id)
    ON CONFLICT (room_id, user_id) DO UPDATE
    SET left_at = NULL; -- Re-join if they previously left
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to safely remove member from a room
CREATE OR REPLACE FUNCTION public.unsync_chat_member(p_room_id UUID, p_user_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE public.chat_members
    SET left_at = NOW()
    WHERE room_id = p_room_id AND user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- 2. GLOBAL CHAT SYNC (On User Create)
-- =============================================

CREATE OR REPLACE FUNCTION public.on_user_created_sync_chat()
RETURNS TRIGGER AS $$
DECLARE
    v_global_id UUID;
    v_announcement_id UUID;
BEGIN
    SELECT id INTO v_global_id FROM chat_rooms WHERE room_type = 'global' LIMIT 1;
    SELECT id INTO v_announcement_id FROM chat_rooms WHERE room_type = 'announcement' LIMIT 1;
    IF v_global_id IS NOT NULL THEN PERFORM public.sync_chat_member(v_global_id, NEW.id); END IF;
    IF v_announcement_id IS NOT NULL THEN PERFORM public.sync_chat_member(v_announcement_id, NEW.id); END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_sync_global_chat_on_create ON public.users;
CREATE TRIGGER trigger_sync_global_chat_on_create
    AFTER INSERT ON public.users
    FOR EACH ROW EXECUTE FUNCTION public.on_user_created_sync_chat();

-- =============================================
-- 3. STORE CHAT SYNC (On Store Assignment)
-- =============================================

CREATE OR REPLACE FUNCTION public.on_store_assignment_sync_chat()
RETURNS TRIGGER AS $$
DECLARE
    v_room_id UUID;
    v_store_name TEXT;
BEGIN
    SELECT id INTO v_room_id FROM public.chat_rooms WHERE store_id = NEW.store_id AND room_type = 'toko' LIMIT 1;
    IF v_room_id IS NULL THEN
        SELECT store_name INTO v_store_name FROM public.stores WHERE id = NEW.store_id;
        INSERT INTO public.chat_rooms (room_type, name, store_id, is_active)
        VALUES ('toko', 'Toko: ' || COALESCE(v_store_name, 'Unknown'), NEW.store_id, true)
        RETURNING id INTO v_room_id;
    END IF;
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.active = TRUE) THEN
        PERFORM public.sync_chat_member(v_room_id, NEW.promotor_id);
    ELSIF TG_OP = 'UPDATE' AND NEW.active = FALSE THEN
        PERFORM public.unsync_chat_member(v_room_id, NEW.promotor_id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_sync_store_chat_assignment ON public.assignments_promotor_store;
CREATE TRIGGER trigger_sync_store_chat_assignment
    AFTER INSERT OR UPDATE ON public.assignments_promotor_store
    FOR EACH ROW EXECUTE FUNCTION public.on_store_assignment_sync_chat();

-- =============================================
-- 4. TEAM CHAT SYNC (On SATOR-Promotor Hierarchy)
-- =============================================

CREATE OR REPLACE FUNCTION public.on_hierarchy_sator_sync_chat()
RETURNS TRIGGER AS $$
DECLARE
    v_room_id UUID;
    v_full_name TEXT;
BEGIN
    SELECT full_name INTO v_full_name FROM public.users WHERE id = NEW.sator_id;
    SELECT id INTO v_room_id FROM public.chat_rooms WHERE sator_id = NEW.sator_id AND room_type = 'tim' LIMIT 1;
    IF v_room_id IS NULL THEN
        INSERT INTO public.chat_rooms (room_type, name, sator_id, is_active)
        VALUES ('tim', 'Tim SATOR: ' || COALESCE(v_full_name, 'Unknown'), NEW.sator_id, true)
        RETURNING id INTO v_room_id;
    END IF;
    PERFORM public.sync_chat_member(v_room_id, NEW.sator_id);
    IF TG_OP = 'INSERT' OR (TG_OP = 'UPDATE' AND NEW.active = TRUE) THEN
        PERFORM public.sync_chat_member(v_room_id, NEW.promotor_id);
    ELSIF TG_OP = 'UPDATE' AND NEW.active = FALSE THEN
        PERFORM public.unsync_chat_member(v_room_id, NEW.promotor_id);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trigger_sync_team_chat_hierarchy ON public.hierarchy_sator_promotor;
CREATE TRIGGER trigger_sync_team_chat_hierarchy
    AFTER INSERT OR UPDATE ON public.hierarchy_sator_promotor
    FOR EACH ROW EXECUTE FUNCTION public.on_hierarchy_sator_sync_chat();

-- =============================================
-- 5. INITIAL SYNC FUNCTION (Run once after migration)
-- =============================================

CREATE OR REPLACE FUNCTION public.initial_chat_sync()
RETURNS VOID AS $$
DECLARE
    r RECORD;
    v_global_id UUID;
    v_announcement_id UUID;
BEGIN
    SELECT id INTO v_global_id FROM chat_rooms WHERE room_type = 'global' LIMIT 1;
    SELECT id INTO v_announcement_id FROM chat_rooms WHERE room_type = 'announcement' LIMIT 1;

    -- Sync All Users to Global & Announcement
    FOR r IN SELECT id FROM public.users WHERE deleted_at IS NULL LOOP
        IF v_global_id IS NOT NULL THEN
            PERFORM public.sync_chat_member(v_global_id, r.id);
        END IF;
        IF v_announcement_id IS NOT NULL THEN
            PERFORM public.sync_chat_member(v_announcement_id, r.id);
        END IF;
    END LOOP;

    -- Sync Store Assignments (trigger akan handle)
    FOR r IN SELECT promotor_id, store_id FROM public.assignments_promotor_store WHERE active = TRUE LOOP
        UPDATE public.assignments_promotor_store SET created_at = NOW() 
        WHERE promotor_id = r.promotor_id AND store_id = r.store_id;
    END LOOP;

    -- Sync Team Hierarchy (trigger akan handle)
    FOR r IN SELECT sator_id, promotor_id FROM public.hierarchy_sator_promotor WHERE active = TRUE LOOP
        UPDATE public.hierarchy_sator_promotor SET created_at = NOW() 
        WHERE sator_id = r.sator_id AND promotor_id = r.promotor_id;
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =============================================
-- NOTE: After running this migration, execute:
-- SELECT public.initial_chat_sync();
-- =============================================
