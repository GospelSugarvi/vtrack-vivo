-- User Quick Menu Preferences System
-- Allow users to customize their home screen quick menu

-- ==========================================
-- 1. USER QUICK MENU PREFERENCES TABLE
-- ==========================================
CREATE TABLE user_quick_menu_preferences (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    menu_id TEXT NOT NULL,
    menu_position INTEGER NOT NULL CHECK (menu_position >= 0 AND menu_position < 8), -- Max 8 items in grid
    active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- One menu per position per user
    UNIQUE(user_id, menu_position),
    -- One menu can only appear once per user
    UNIQUE(user_id, menu_id)
);

-- Add indexes
CREATE INDEX idx_user_quick_menu_user ON user_quick_menu_preferences(user_id);
CREATE INDEX idx_user_quick_menu_active ON user_quick_menu_preferences(active);

-- ==========================================
-- 2. DEFAULT MENU ITEMS (Reference)
-- ==========================================
-- This is just for reference, actual menu list is in Flutter code
-- Available menu_ids:
-- - 'clock_in' (Absen)
-- - 'sell_out' (Jual)
-- - 'stock_input' (Stok)
-- - 'stock_validation' (Validasi)
-- - 'search_stock' (Cari Stok)
-- - 'promotion' (Promosi)
-- - 'follower' (Follower)
-- - 'allbrand' (AllBrand)
-- - 'jadwal' (Jadwal)
-- - 'imei_normalization' (IMEI Normal)

-- ==========================================
-- 3. RLS POLICIES
-- ==========================================
ALTER TABLE user_quick_menu_preferences ENABLE ROW LEVEL SECURITY;

-- Users can manage their own preferences
CREATE POLICY "Users can manage own quick menu preferences" ON user_quick_menu_preferences
    FOR ALL USING (auth.uid() = user_id);

-- ==========================================
-- 4. TRIGGERS
-- ==========================================
CREATE OR REPLACE FUNCTION update_user_quick_menu_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_user_quick_menu_updated_at
    BEFORE UPDATE ON user_quick_menu_preferences
    FOR EACH ROW
    EXECUTE FUNCTION update_user_quick_menu_updated_at();

-- ==========================================
-- 5. HELPER FUNCTIONS
-- ==========================================

-- Function to initialize default menu for new user
CREATE OR REPLACE FUNCTION initialize_default_quick_menu(p_user_id UUID)
RETURNS VOID AS $$
BEGIN
    -- Insert default 8 menu items
    INSERT INTO user_quick_menu_preferences (user_id, menu_id, menu_position, active)
    VALUES
        (p_user_id, 'clock_in', 0, true),
        (p_user_id, 'sell_out', 1, true),
        (p_user_id, 'stock_input', 2, true),
        (p_user_id, 'stock_validation', 3, true),
        (p_user_id, 'search_stock', 4, true),
        (p_user_id, 'promotion', 5, true),
        (p_user_id, 'follower', 6, true),
        (p_user_id, 'allbrand', 7, true)
    ON CONFLICT (user_id, menu_position) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to get user's quick menu
CREATE OR REPLACE FUNCTION get_user_quick_menu(p_user_id UUID)
RETURNS TABLE (
    menu_id TEXT,
    menu_position INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        uqm.menu_id,
        uqm.menu_position
    FROM user_quick_menu_preferences uqm
    WHERE uqm.user_id = p_user_id
    AND uqm.active = true
    ORDER BY uqm.menu_position;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Function to reorder menu items
CREATE OR REPLACE FUNCTION reorder_quick_menu(
    p_user_id UUID,
    p_menu_positions JSONB -- Format: [{"menu_id": "clock_in", "menu_position": 0}, ...]
)
RETURNS VOID AS $$
DECLARE
    menu_item JSONB;
BEGIN
    -- Update positions for each menu item
    FOR menu_item IN SELECT * FROM jsonb_array_elements(p_menu_positions)
    LOOP
        UPDATE user_quick_menu_preferences
        SET menu_position = (menu_item->>'menu_position')::INTEGER
        WHERE user_id = p_user_id
        AND menu_id = menu_item->>'menu_id';
    END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION initialize_default_quick_menu TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_quick_menu TO authenticated;
GRANT EXECUTE ON FUNCTION reorder_quick_menu TO authenticated;

-- Add comments
COMMENT ON TABLE user_quick_menu_preferences IS 'User customizable quick menu preferences for home screen';
COMMENT ON FUNCTION initialize_default_quick_menu IS 'Initialize default quick menu for new user';
COMMENT ON FUNCTION get_user_quick_menu IS 'Get user quick menu ordered by position';
COMMENT ON FUNCTION reorder_quick_menu IS 'Reorder user quick menu items';
