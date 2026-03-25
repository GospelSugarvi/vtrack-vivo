-- Check shift settings in database

-- 1. Check all shift settings
SELECT * FROM shift_settings ORDER BY area, shift_type;

-- 2. Check what admin has set for Kupang area
SELECT 
    shift_type,
    TO_CHAR(start_time, 'HH24:MI') as start_time,
    TO_CHAR(end_time, 'HH24:MI') as end_time,
    area,
    active
FROM shift_settings
WHERE area = 'Kupang' OR area = 'default'
ORDER BY area, shift_type;

-- 3. Check promotor's area (example: Yohanis)
SELECT id, full_name, area, role
FROM users
WHERE role = 'promotor'
AND full_name ILIKE '%yohanis%';

-- 4. Test the get_shift_display function
SELECT 
    'pagi' as shift,
    get_shift_display('pagi', 'Kupang') as kupang_time,
    get_shift_display('pagi', 'default') as default_time;

SELECT 
    'siang' as shift,
    get_shift_display('siang', 'Kupang') as kupang_time,
    get_shift_display('siang', 'default') as default_time;
