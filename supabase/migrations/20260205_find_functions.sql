-- ==========================================================
-- FIX ALL FUNCTIONS: Hapus referensi ideal_qty
-- ==========================================================

-- Fix get_store_stock_status (jika masih ada)
-- Function ini perlu di-recreate tanpa ideal_qty

-- Cek dulu function yang aktif
SELECT proname FROM pg_proc WHERE proname = 'get_store_stock_status';
