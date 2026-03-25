-- Allow multiple attendance entries per user per day.
-- Previous schema enforced one row/day with UNIQUE(user_id, attendance_date).

ALTER TABLE public.attendance
DROP CONSTRAINT IF EXISTS attendance_user_id_attendance_date_key;

-- Safety for environments where uniqueness was created as index directly.
DROP INDEX IF EXISTS attendance_user_id_attendance_date_key;

-- Keep query performance for daily filtering without uniqueness.
CREATE INDEX IF NOT EXISTS idx_attendance_user_date_nonuniq
ON public.attendance(user_id, attendance_date);
