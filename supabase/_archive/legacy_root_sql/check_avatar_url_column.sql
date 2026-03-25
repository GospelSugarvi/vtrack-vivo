-- Check if avatar_url column exists in users table

SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'users'
AND column_name = 'avatar_url';

-- If not exists, add it
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'users' AND column_name = 'avatar_url'
    ) THEN
        ALTER TABLE users ADD COLUMN avatar_url TEXT;
        COMMENT ON COLUMN users.avatar_url IS 'URL to user profile photo (Cloudinary)';
    END IF;
END $$;

-- Verify
SELECT id, full_name, avatar_url 
FROM users 
LIMIT 5;
