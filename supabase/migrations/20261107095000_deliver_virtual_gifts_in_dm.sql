-- Make every virtual gift a durable event in the normal DM timeline.
-- The member_gifts row remains the source of truth for price, redemption and status.
-- This message marker lets the existing inbox and incoming-message Realtime path
-- wake up both participants without exposing gift metadata in a plain text message.

create unique index if not exists messages_match_gift_marker_uidx
  on public.messages(body)
  where body ~ '^\\[\\[MATCH_GIFT:[0-9a-f-]{36}\\]\\]$';

create or replace function public.notify_match_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_name text;
begin
  -- Gift notifications are sent by notify_member_gift_received().
  -- Do not create a second, generic "New message" notification for the marker.
  if new.body ~ '^\\[\\[MATCH_GIFT:[0-9a-f-]{36}\\]\\]$' then
    return new;
  end if;

  if new.sender_id = new.receiver_id then
    return new;
  end if;

  select display_name into v_name
  from public.profiles
  where id = new.sender_id;

  insert into public.notifications(user_id, type, title, body, related_user_id)
  values (
    new.receiver_id,
    'message',
    'New message',
    coalesce(v_name, 'A member') || ' sent you a message.',
    new.sender_id
  );
  return new;
end;
$function$;

create or replace function public.create_gift_dm_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.messages(sender_id, receiver_id, body, created_at)
  values (
    new.sender_id,
    new.recipient_id,
    '[[MATCH_GIFT:' || new.id::text || ']]',
    new.created_at
  )
  on conflict (body) where body ~ '^\\[\\[MATCH_GIFT:[0-9a-f-]{36}\\]\\]$'
  do nothing;

  return new;
end;
$function$;

revoke all on function public.create_gift_dm_message() from public, anon, authenticated;

drop trigger if exists create_gift_dm_message on public.member_gifts;
create trigger create_gift_dm_message
after insert on public.member_gifts
for each row
execute function public.create_gift_dm_message();

-- Backfill existing gifts so they also appear in both participants' DMs.
insert into public.messages(sender_id, receiver_id, body, created_at)
select
  g.sender_id,
  g.recipient_id,
  '[[MATCH_GIFT:' || g.id::text || ']]',
  g.created_at
from public.member_gifts g
where not exists (
  select 1
  from public.messages m
  where m.body = '[[MATCH_GIFT:' || g.id::text || ']]'
)
on conflict (body) where body ~ '^\\[\\[MATCH_GIFT:[0-9a-f-]{36}\\]\\]$'
do nothing;

-- Realtime must publish both ordinary message events and gift state changes.
do $publication$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'messages'
    ) then
      execute 'alter publication supabase_realtime add table public.messages';
    end if;

    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime'
        and schemaname = 'public'
        and tablename = 'member_gifts'
    ) then
      execute 'alter publication supabase_realtime add table public.member_gifts';
    end if;
  end if;
end;
$publication$;

alter table public.member_gifts replica identity full;
