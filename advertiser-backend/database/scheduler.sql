-- Run in the isolated advertiser Supabase project after bootstrap.sql.
-- Supabase Cron (pg_cron) invokes a database-owned function every minute.
create extension if not exists pg_cron;

select cron.unschedule(jobid)
from cron.job
where jobname = 'the-match-advertising-campaign-clock';

select cron.schedule(
  'the-match-advertising-campaign-clock',
  '* * * * *',
  'select private.process_advertising_campaign_clock_cron();'
);
