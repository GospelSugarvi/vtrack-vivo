alter table public.attendance
  drop constraint if exists attendance_report_category_check;

alter table public.attendance
  drop column if exists type,
  drop column if exists report_category,
  drop column if exists latitude,
  drop column if exists longitude;
