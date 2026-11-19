-- Notify all other members when an event first becomes publicly published.
-- Pending submissions never generate notifications; admin approval remains the publication gate.

create or replace function public.notify_members_when_event_is_published()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  if new.status = 'published' then
    if tg_op = 'INSERT' or old.status is distinct from 'published' then
      insert into public.notifications (
        user_id,
        type,
        title,
        body,
        related_user_id,
        is_read
      )
      select
        p.id,
        'event_published',
        'New event posted',
        new.title || ' · ' || new.city,
        new.organiser_id,
        false
      from public.profiles as p
      where p.id <> new.organiser_id;
    end if;
  end if;

  return new;
end;
$$;

-- This function is intended to run only as a table trigger, never as a client RPC.
revoke all on function public.notify_members_when_event_is_published() from public;
revoke all on function public.notify_members_when_event_is_published() from anon;
revoke all on function public.notify_members_when_event_is_published() from authenticated;

drop trigger if exists match_events_notify_members_on_publish on public.match_events;
create trigger match_events_notify_members_on_publish
after insert or update of status on public.match_events
for each row
execute function public.notify_members_when_event_is_published();

-- Enable INSERT events for the per-member realtime notification subscription.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (
       select 1
       from pg_publication_tables
       where pubname = 'supabase_realtime'
         and schemaname = 'public'
         and tablename = 'notifications'
     ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end;
$$;
