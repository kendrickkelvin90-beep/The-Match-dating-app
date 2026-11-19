-- Community isolation for event listings and event-published notifications.
-- The community is derived from the organiser's private, saved onboarding choice.
alter table public.match_events
  add column if not exists community text;

create or replace function public.set_match_event_community()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public
as $
declare
  organiser_community text;
begin
  if tg_op = 'INSERT' then
    select mo.answers ->> 'dating_community'
      into organiser_community
    from public.member_onboarding as mo
    where mo.user_id = new.organiser_id;

    if organiser_community is null or organiser_community not in ('lgbtq', 'straight') then
      raise exception 'Choose a valid private dating community before submitting an event.';
    end if;

    new.community := organiser_community;
  else
    -- The event audience is permanent and cannot be changed by an organiser
    -- or by a later profile edit.
    new.community := old.community;
  end if;

  return new;
end;
$;

revoke all on function public.set_match_event_community() from public;
revoke all on function public.set_match_event_community() from anon;
revoke all on function public.set_match_event_community() from authenticated;

drop trigger if exists match_events_set_community on public.match_events;
create trigger match_events_set_community
before insert or update on public.match_events
for each row
execute function public.set_match_event_community();

-- Backfill any existing event rows before enforcing the new required field.
update public.match_events e
set community = mo.answers ->> 'dating_community'
from public.member_onboarding mo
where mo.user_id = e.organiser_id
  and mo.answers ->> 'dating_community' in ('lgbtq', 'straight')
  and e.community is null;

do $
begin
  if exists (select 1 from public.match_events where community is null) then
    raise exception 'Cannot enable event community isolation: an existing event organiser has no valid saved dating community.';
  end if;
end;
$;

alter table public.match_events
  alter column community set not null;

alter table public.match_events
  add constraint match_events_community_check
  check (community in ('lgbtq', 'straight'));

drop policy if exists "Members can view published events" on public.match_events;
create policy "Members can view published events in their own community"
on public.match_events
for select
to authenticated
using (
  (status = 'published'
    and community = (
      select mo.answers ->> 'dating_community'
      from public.member_onboarding as mo
      where mo.user_id = (select auth.uid())
    ))
  or organiser_id = (select auth.uid())
  or is_match_admin()
);

alter table public.notifications
  drop constraint if exists notifications_type_check;
alter table public.notifications
  add constraint notifications_type_check
  check (type = any (array[
    'verification_approved','verification_rejected','verification_reminder',
    'verification_grace_expired','like','message','premium_welcome',
    'premium_expired','story_uploaded','story_limit','membership_payment_rejected',
    'coins_credited','coin_purchase_rejected','account_suspended','account_banned',
    'event_published'
  ]));

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
        is_read,
        action_url,
        action_label
      )
      select
        p.id,
        'event_published',
        'New event posted',
        new.title || ' · ' || new.city,
        new.organiser_id,
        false,
        'event:' || new.id::text,
        'View event'
      from public.member_onboarding as mo
      where mo.user_id <> new.organiser_id
        and mo.answers ->> 'dating_community' = new.community
        and mo.answers ->> 'dating_community' in ('lgbtq', 'straight');
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

-- Child event assets and ticket options must follow the same community boundary.
drop policy if exists "Members view permitted event poster assets" on public.match_event_poster_assets;
create policy "Members view permitted event poster assets"
on public.match_event_poster_assets
for select
to authenticated
using (
  organiser_id = (select auth.uid())
  or is_match_admin()
  or exists (
    select 1
    from public.match_events e
    where e.id = match_event_poster_assets.event_id
      and e.status = 'published'
      and e.community = (
        select mo.answers ->> 'dating_community'
        from public.member_onboarding mo
        where mo.user_id = (select auth.uid())
      )
  )
);

drop policy if exists "Members and organisers can view permitted ticket options" on public.match_event_ticket_types;
create policy "Members and organisers can view permitted ticket options"
on public.match_event_ticket_types
for select
to authenticated
using (
  (
    is_active
    and exists (
      select 1
      from public.match_events e
      where e.id = match_event_ticket_types.event_id
        and e.status = 'published'
        and e.community = (
          select mo.answers ->> 'dating_community'
          from public.member_onboarding mo
          where mo.user_id = (select auth.uid())
        )
    )
  )
  or exists (
    select 1
    from public.match_events e
    where e.id = match_event_ticket_types.event_id
      and e.organiser_id = (select auth.uid())
      and e.status = 'pending_review'
  )
  or is_match_admin()
);

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
