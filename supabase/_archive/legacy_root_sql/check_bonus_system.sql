-- SQL untuk cek bonus system tables

-- 1. Cek kolom di bonus_rules
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'bonus_rules' 
ORDER BY ordinal_position;



-- 3. Cek tabel special_rewards ada
SELECT COUNT(*) as special_rewards_count FROM special_rewards;

-- 4. Cek tabel kpi_settings ada
SELECT COUNT(*) as kpi_settings_count FROM kpi_settings;

-- 5. Cek kolom promotor_status di users
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'users' AND column_name = 'promotor_status';
