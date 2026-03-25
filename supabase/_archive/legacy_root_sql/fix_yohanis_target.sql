-- Fix Yohanis target - set omzet and fokus total

-- Update user_targets untuk Yohanis
UPDATE user_targets
SET 
    target_omzet = 150000000,  -- 150 juta
    target_fokus_total = 30     -- Total 30 unit (Y400:10 + Y21D:10 + V60:10)
WHERE user_id = 'a85b7470-47f8-481c-9dd0-d77ad851b4a7'
AND period_id = 'ee5bb3c5-a1fd-4833-a554-a4bbc4359783';

-- Refresh view
REFRESH MATERIALIZED VIEW v_target_dashboard;

-- Verify
SELECT 
    'UPDATED TARGET' as check,
    full_name,
    period_name,
    target_omzet,
    target_fokus_total,
    actual_omzet,
    actual_fokus_total,
    achievement_omzet_pct,
    achievement_fokus_pct,
    time_gone_pct,
    status_omzet,
    status_fokus
FROM v_target_dashboard
WHERE full_name ILIKE '%tipnoni%'
AND period_name = 'Januari 2026';
