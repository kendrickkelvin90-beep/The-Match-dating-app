-- Automatically expire published Match events when their start date/time arrives.
-- Production SQL was installed directly; this migration records it for repo parity.
create or replace function public.expire_match_events()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare affected integer;
begin
  update public.match_events
  set status = 'completed', updated_at = now()
  where status = 'published'
    and starts_at <= now();
  get diagnostics affected = row_count;
  return affected;
end;
$$;

revoke all on function public.expire_match_events() from public, anon, authenticated;
grant execute on function public.expire_match_events() to service_role;

select cron.unschedule(jobid)
from cron.job
where jobname = 'expire-match-events-hourly';

select cron.schedule(
  'expire-match-events-hourly',
  '0 * * * *',
  $$select public.expire_match_events();$$
);
