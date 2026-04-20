create extension if not exists pg_cron;

create or replace function public.dispatch_pending_live_feed_ai_comment_jobs()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.ai_sales_comment_jobs j
    where j.status = 'pending'
    limit 1
  ) then
    perform public.dispatch_live_feed_ai_sales_comment_worker(5);
  end if;

  if exists (
    select 1
    from public.ai_feed_comment_reply_jobs r
    where r.status = 'pending'
    limit 1
  ) then
    perform public.dispatch_live_feed_ai_sales_comment_worker(5);
  end if;
end;
$$;

select cron.unschedule(jobid)
from cron.job
where jobname = 'live-feed-ai-comment-dispatch-watchdog';

select cron.schedule(
  'live-feed-ai-comment-dispatch-watchdog',
  '* * * * *',
  $$select public.dispatch_pending_live_feed_ai_comment_jobs();$$
);
