-- Automated Premium expiry reminders: 7 days and 2 days before expiry.
-- Notifications are inserted into the existing notifications table, whose
-- INSERT trigger already delivers OneSignal push notifications.
create extension if not exists pg_cron with schema pg_catalog;

alter table public.premium_memberships
  add column if not exists premium_expiry_7d_notified_at timestamptz,
  add column if not exists premium_expiry_2d_notified_at timestamptz;

alter table public.notifications
  add column if not exists action_url text,
  add column if not exists action_label text;

create or replace function public.process_premium_expiry_reminders()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_7d integer := 0;
  v_2d integer := 0;
begin
  with due as (
    select pm.user_id, pm.premium_until, p.display_name
    from public.premium_memberships pm
    left join public.profiles p on p.id = pm.user_id
    where pm.premium_until > now()
      and pm.premium_until <= now() + interval '8 days'
      and pm.premium_until > now() + interval '6 days'
      and pm.premium_expiry_7d_notified_at is null
    for update of pm skip locked
  ), inserted as (
    insert into public.notifications (user_id, type, title, body, action_url, action_label)
    select user_id, 'premium_expiring',
      'Your Premium membership is expiring soon',
      'Hi ' || coalesce(nullif(trim(display_name), ''), 'there') ||
      ', your Premium membership will expire on ' ||
      to_char(premium_until at time zone 'Africa/Lagos', 'DD Mon YYYY') ||
      '. Would you like to renew and continue enjoying your Premium benefits?',
      '/#premium',
      'Yes, Renew'
    from due
    returning user_id
  )
  select count(*) into v_7d from inserted;

  update public.premium_memberships pm
  set premium_expiry_7d_notified_at = now()
  where pm.user_id in (
    select n.user_id from public.notifications n
    where n.type = 'premium_expiring'
      and n.created_at >= now() - interval '1 minute'
      and n.body like '%will expire on%'
  )
  and pm.premium_expiry_7d_notified_at is null
  and pm.premium_until > now() + interval '6 days';

  with due as (
    select pm.user_id, pm.premium_until, p.display_name
    from public.premium_memberships pm
    left join public.profiles p on p.id = pm.user_id
    where pm.premium_until > now()
      and pm.premium_until <= now() + interval '3 days'
      and pm.premium_until > now() + interval '1 day'
      and pm.premium_expiry_2d_notified_at is null
    for update of pm skip locked
  ), inserted as (
    insert into public.notifications (user_id, type, title, body, action_url, action_label)
    select user_id, 'premium_expiring_soon',
      'Your Premium membership expires in 2 days',
      'Hi ' || coalesce(nullif(trim(display_name), ''), 'there') ||
      ', your Premium membership will expire on ' ||
      to_char(premium_until at time zone 'Africa/Lagos', 'DD Mon YYYY') ||
      '. Renew now to keep your Premium benefits.',
      '/#premium',
      'Yes, Renew'
    from due
    returning user_id
  )
  select count(*) into v_2d from inserted;

  update public.premium_memberships pm
  set premium_expiry_2d_notified_at = now()
  where pm.user_id in (
    select n.user_id from public.notifications n
    where n.type = 'premium_expiring_soon'
      and n.created_at >= now() - interval '1 minute'
  )
  and pm.premium_expiry_2d_notified_at is null
  and pm.premium_until > now() + interval '1 day'
  and pm.premium_until <= now() + interval '3 days';

  return jsonb_build_object('seven_day_reminders', v_7d, 'two_day_reminders', v_2d);
end;
$$;

-- Only the database scheduler (postgres role) may execute this worker.
revoke all on function public.process_premium_expiry_reminders() from public, anon, authenticated;
grant execute on function public.process_premium_expiry_reminders() to postgres;

-- Run at 09:00 Lagos time (08:00 UTC) every day.
select cron.schedule(
  'premium-expiry-reminders',
  '0 8 * * *',
  $$select public.process_premium_expiry_reminders();$$
);
