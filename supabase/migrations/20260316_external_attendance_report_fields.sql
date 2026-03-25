alter table public.attendance
  add column if not exists main_attendance_proof_url text,
  add column if not exists main_attendance_status text,
  add column if not exists report_category text;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'attendance_main_attendance_status_check'
  ) then
    alter table public.attendance
      add constraint attendance_main_attendance_status_check
      check (
        main_attendance_status is null
        or main_attendance_status in ('on_time', 'late')
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'attendance_report_category_check'
  ) then
    alter table public.attendance
      add constraint attendance_report_category_check
      check (
        report_category is null
        or report_category in (
          'normal',
          'late',
          'travel',
          'system_issue',
          'special_permission',
          'sick',
          'leave',
          'management_holiday'
        )
      );
  end if;
end $$;

update public.attendance
set
  clock_in = coalesce(clock_in, created_at),
  clock_in_location = coalesce(
    clock_in_location,
    jsonb_build_object('lat', latitude, 'lng', longitude)
  )
where type = 'clock_in'
  and (clock_in is null or clock_in_location is null);
