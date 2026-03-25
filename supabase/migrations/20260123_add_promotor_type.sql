-- Add promotor_type column to users table
-- To differentiate between Official and Training promotors

ALTER TABLE users 
ADD COLUMN IF NOT EXISTS promotor_type TEXT DEFAULT 'official' 
CHECK (promotor_type IN ('official', 'training'));

-- Add index for faster queries
CREATE INDEX IF NOT EXISTS idx_users_promotor_type ON users(promotor_type);

-- Add comment
COMMENT ON COLUMN users.promotor_type IS 'Type of promotor: official (full benefits) or training (reduced benefits)';

-- Update existing promotor users to official (default)
UPDATE users 
SET promotor_type = 'official' 
WHERE role = 'promotor' 
AND promotor_type IS NULL;
