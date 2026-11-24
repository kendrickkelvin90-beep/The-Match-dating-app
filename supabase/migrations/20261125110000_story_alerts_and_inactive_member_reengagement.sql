-- Friendly Story activity alerts and a capped inactive-member re-engagement sequence.
begin;

alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check
  check (type = any (array[
    'verification_approved','verification_rejected','verification_reminder',
    'verification_grace_expired','like','message','premium_welcome',
    'premium_expired','story_uploaded','story_limit','membership_payment_rejected',
    'coins_credited','coin_purchase_rejected','account_suspended','account_banned',
    'event_published','premium_expiring','premium_expiring_soon','member_welcome_back'
  ]));

-- Reusable audience check for a specific viewer/owner pair. The regular
-- RLS helper uses auth.uid() and cannot be called for each notification recipient
-- from a multi-recipient trigger, so this mirrors its "everyone" eligibility.
create or replace function private.can_view_story_between(
  p_viewer_id uuid,
  p_owner_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    p_viewer_id is not null
    and p_owner_id is not null
    and p_owner_id <> p_viewer_id
    and exists (
      select 1
      from public.profiles viewer
      join public.profiles owner on owner.id = p_owner_id
      join public.member_onboarding viewer_onboarding on viewer_onboarding.user_id = viewer.id
      join public.member_onboarding owner_onboarding on owner_onboarding.user_id = owner.id
      where viewer.id = p_viewer_id
        and public.is_match_profile_complete(viewer.id)
        and public.is_match_profile_complete(owner.id)
        and viewer.age >= 18
        and owner.age >= 18
        and private.match_preference_accepts_gender(viewer.interested_in, owner.gender_identity)
        and private.match_preference_accepts_gender(owner.interested_in, viewer.gender_identity)
        and private.member_meets_partner_preferences(viewer.id, owner.id)
        and private.member_meets_partner_preferences(owner.id, viewer.id)
        and private.member_dating_community(viewer.id) is not null
        and private.member_dating_community(owner.id) = private.member_dating_community(viewer.id)
        and (select count(*) from public.profile_photos viewer_photo where viewer_photo.user_id = viewer.id) >= 2
        and (select count(*) from public.profile_photos owner_photo where owner_photo.user_id = owner.id) >= 2
        and not exists (
          select 1 from public.member_blocks block_record
          where (block_record.blocker_id = viewer.id and block_record.blocked_id = owner.id)
             or (block_record.blocker_id = owner.id and block_record.blocked_id = viewer.id)
        )
        and not exists (
          select 1 from public.member_moderation moderation
          where moderation.user_id in (viewer.id, owner.id)
            and (
              moderation.status = 'banned'
              or (moderation.status = 'suspended' and moderation.expires_at > now())
            )
        )
    );
$function$;

revoke all on function private.can_view_story_between(uuid,uuid) from public, anon, authenticated;

-- Match-audience Story access requires a mutual like in addition to the
-- connection checks. This explicit pair helper also works when a trusted
-- server-side insert has no end-user auth.uid() context.
create or replace function private.can_view_story_match_between(
  p_viewer_id uuid,
  p_owner_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    p_viewer_id is not null
    and p_owner_id is not null
    and p_viewer_id <> p_owner_id
    and exists (
      select 1 from public.likes a
      where a.liker_id = p_viewer_id and a.liked_id = p_owner_id
    )
    and exists (
      select 1 from public.likes b
      where b.liker_id = p_owner_id and b.liked_id = p_viewer_id
    )
    and not exists (
      select 1 from public.member_blocks block_record
      where (block_record.blocker_id = p_viewer_id and block_record.blocked_id = p_owner_id)
         or (block_record.blocker_id = p_owner_id and block_record.blocked_id = p_viewer_id)
    )
    and not exists (
      select 1 from public.member_moderation moderation
      where moderation.user_id in (p_viewer_id, p_owner_id)
        and (
          moderation.status = 'banned'
          or (moderation.status = 'suspended' and moderation.expires_at > now())
        )
    );
$function$;

revoke all on function private.can_view_story_match_between(uuid,uuid) from public, anon, authenticated;

-- Story alerts go only to members who can actually view the Story under its audience rules.
create or replace function public.notify_connected_members_of_story()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_name text;
  v_lane text;
begin
  select coalesce(nullif(btrim(p.display_name), ''), 'A member')
    into v_name
  from public.profiles p
  where p.id = new.user_id;

  v_lane := private.member_dating_community(new.user_id);
  if v_lane is null then return new; end if;

  insert into public.notifications(
    user_id, type, title, body, related_user_id, is_read, action_url
  )
  select distinct candidate.user_id,
    'story_uploaded',
    v_name || ' just uploaded a Story',
    v_name || ' just shared a new Story. Want to check it out? Open Discover to watch.',
    new.user_id,
    false,
    '/#discover'
  from (
    select m.sender_id as user_id
    from public.messages m
    where m.receiver_id = new.user_id
    union
    select m.receiver_id as user_id
    from public.messages m
    where m.sender_id = new.user_id
    union
    select l.liker_id as user_id
    from public.likes l
    where l.liked_id = new.user_id
      and exists (
        select 1 from public.likes reciprocal
        where reciprocal.liker_id = new.user_id
          and reciprocal.liked_id = l.liker_id
      )
  ) candidate
  where candidate.user_id <> new.user_id
    and (
      (new.audience = 'everyone' and private.can_view_story_between(candidate.user_id, new.user_id))
      or (
        new.audience = 'matches'
        and private.can_view_story_match_between(candidate.user_id, new.user_id)
      )
    )
    and not exists (
      select 1 from public.member_blocks b
      where (b.blocker_id = candidate.user_id and b.blocked_id = new.user_id)
         or (b.blocker_id = new.user_id and b.blocked_id = candidate.user_id)
    )
    and not exists (
      select 1 from public.notifications prior
      where prior.user_id = candidate.user_id
        and prior.related_user_id = new.user_id
        and prior.type = 'story_uploaded'
        and prior.created_at > now() - interval '12 hours'
    );

  return new;
end;
$function$;

revoke all on function public.notify_connected_members_of_story() from public, anon, authenticated;
drop trigger if exists stories_notify_connected_members on public.stories;
create trigger stories_notify_connected_members
after insert on public.stories
for each row execute function public.notify_connected_members_of_story();

-- Track actual app presence separately from the daily check-in streak.
-- The existing member_consistency.last_active_date is a rewards/check-in date,
-- so it must not be repurposed as a general activity timestamp.
create table if not exists private.member_activity_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_seen_at timestamptz not null,
  updated_at timestamptz not null default now()
);
alter table private.member_activity_state enable row level security;
revoke all on private.member_activity_state from public, anon, authenticated, service_role;

-- Seed existing members from their most recent Auth sign-in so the first
-- reminder cycle has a sensible baseline before they next open the app.
insert into private.member_activity_state(user_id,last_seen_at,updated_at)
select id, coalesce(last_sign_in_at,created_at), now()
from auth.users
on conflict(user_id) do nothing;

create table if not exists public.member_reengagement_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reminders_sent integer not null default 0 check (reminders_sent between 0 and 2),
  last_reminded_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.member_reengagement_state enable row level security;
revoke all on public.member_reengagement_state from public, anon, authenticated;

-- Called on app start, sign-in, and when the member returns to the foreground.
-- The RPC takes no user ID, so a member can update only their own presence.
create or replace function public.record_member_presence()
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Sign in to record activity.' using errcode = '42501';
  end if;

  insert into private.member_activity_state(user_id,last_seen_at,updated_at)
  values(v_uid,now(),now())
  on conflict(user_id) do update
    set last_seen_at = excluded.last_seen_at,
        updated_at = excluded.updated_at
    where private.member_activity_state.last_seen_at < now() - interval '10 minutes';

  return true;
end;
$function$;
revoke all on function public.record_member_presence() from public, anon;
grant execute on function public.record_member_presence() to authenticated;

create or replace function private.reset_reengagement_on_activity()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.last_seen_at > old.last_seen_at then
    update public.member_reengagement_state
      set reminders_sent = 0, last_reminded_at = null, updated_at = now()
      where user_id = new.user_id;
  end if;
  return new;
end;
$function$;
revoke all on function private.reset_reengagement_on_activity() from public, anon, authenticated;
drop trigger if exists member_activity_reset_reengagement on private.member_activity_state;
create trigger member_activity_reset_reengagement
after update of last_seen_at on private.member_activity_state
for each row execute function private.reset_reengagement_on_activity();

create or replace function private.process_inactive_member_reminders()
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare v_count integer := 0;
begin
  with due as (
    select activity.user_id,
           coalesce(nullif(btrim(p.display_name), ''), 'there') as display_name
    from private.member_activity_state activity
    left join public.profiles p on p.id = activity.user_id
    left join public.member_reengagement_state state on state.user_id = activity.user_id
    where activity.last_seen_at <= now() - interval '7 days'
      and activity.last_seen_at >= now() - interval '60 days'
      and coalesce(state.reminders_sent, 0) < 2
      and (state.last_reminded_at is null or state.last_reminded_at < now() - interval '14 days')
      and not exists (
        select 1 from public.member_moderation mm
        where mm.user_id = activity.user_id
          and (mm.status = 'banned' or (mm.status = 'suspended' and mm.expires_at > now()))
      )
    for update of activity skip locked
  ), inserted as (
    insert into public.notifications(user_id,type,title,body,is_read)
    select user_id, 'member_welcome_back',
      'We saved you a place ❤️',
      'Hi ' || display_name || ', your connections are waiting. Come back to The Match when you are ready.',
      false
    from due
    returning user_id
  ), state_update as (
    insert into public.member_reengagement_state(user_id,reminders_sent,last_reminded_at,updated_at)
    select user_id, 1, now(), now() from inserted
    on conflict(user_id) do update
      set reminders_sent = least(2, public.member_reengagement_state.reminders_sent + 1),
          last_reminded_at = now(), updated_at = now()
    returning user_id
  )
  select count(*) into v_count from state_update;
  return v_count;
end;
$function$;
revoke all on function private.process_inactive_member_reminders() from public, anon, authenticated;

do $schedule$
begin
  -- Supabase Cron uses UTC; 07:15 UTC is 08:15 in Nigeria (WAT).
  if not exists(select 1 from cron.job where jobname = 'inactive-member-reengagement') then
    perform cron.schedule(
      'inactive-member-reengagement',
      '15 7 * * *',
      $command$select private.process_inactive_member_reminders();$command$
    );
  end if;
end;
$schedule$;

commit;
