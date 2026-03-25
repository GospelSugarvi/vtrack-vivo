-- Allow fullday shift in monthly schedules and schedule change requests.

ALTER TABLE schedules
DROP CONSTRAINT IF EXISTS schedules_shift_type_check;

ALTER TABLE schedules
ADD CONSTRAINT schedules_shift_type_check
CHECK (shift_type IN ('pagi', 'siang', 'fullday', 'libur'));

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'public'
        AND table_name = 'schedule_change_requests'
    ) THEN
        ALTER TABLE schedule_change_requests
        DROP CONSTRAINT IF EXISTS schedule_change_requests_original_shift_type_check;

        ALTER TABLE schedule_change_requests
        ADD CONSTRAINT schedule_change_requests_original_shift_type_check
        CHECK (original_shift_type IN ('pagi', 'siang', 'fullday', 'libur'));

        ALTER TABLE schedule_change_requests
        DROP CONSTRAINT IF EXISTS schedule_change_requests_requested_shift_type_check;

        ALTER TABLE schedule_change_requests
        ADD CONSTRAINT schedule_change_requests_requested_shift_type_check
        CHECK (requested_shift_type IN ('pagi', 'siang', 'fullday', 'libur'));
    END IF;
END $$;
