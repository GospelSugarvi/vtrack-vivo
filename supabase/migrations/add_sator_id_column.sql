-- Add sator_id column to users table to link Promotor to their SATOR
ALTER TABLE users 
ADD COLUMN IF NOT EXISTS sator_id UUID REFERENCES users(id);

-- Optional: Create an index for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_sator_id ON users(sator_id);

-- Comment explaining the column
COMMENT ON COLUMN users.sator_id IS 'Reference to the SATOR (Supervisor Area) user ID for this promotor. Used for grouping promotors into teams.';
