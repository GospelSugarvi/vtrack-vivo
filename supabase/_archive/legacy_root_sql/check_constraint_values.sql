-- Lihat CHECK constraint untuk bonus_type
SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conrelid = 'bonus_rules'::regclass 
AND conname LIKE '%bonus_type%';

-- Atau lihat semua constraints di bonus_rules
SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conrelid = 'bonus_rules'::regclass;
