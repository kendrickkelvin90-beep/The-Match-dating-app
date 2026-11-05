-- A purchased 24-hour Profile Boost grants one first-message ticket.
-- The ticket is consumed only when a first message is successfully inserted.
create table if not exists public.profile_boost_message_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  profile_boost_id uuid not null references public.profile_boosts(id) on delete cascade,
  expires_at timestamptz not null,
  recipient_id uuid references auth.users(id) on delete set null,
  message_id uuid,
  request_key text,
  used_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists profile_boost_message_tickets_available_idx
  on public.profile_boost_message_tickets(user_id, expires_at, created_at)
  where used_at is null;
create unique index if not exists profile_boost_message_tickets_recipient_unique
  on public.profile_boost_message_tickets(user_id, recipient_id)
  where recipient_id is not null;
create unique index if not exists profile_boost_message_tickets_request_unique
  on public.profile_boost_message_tickets(user_id, request_key)
  where request_key is not null;

alter table public.profile_boost_message_tickets enable row level security;
drop policy if exists profile_boost_message_tickets_participant_read on public.profile_boost_message_tickets;
create policy profile_boost_message_tickets_participant_read
  on public.profile_boost_message_tickets
  for select to authenticated
  using (user_id = (select auth.uid()) or recipient_id = (select auth.uid()));
drop policy if exists profile_boost_message_tickets_owner_update on public.profile_boost_message_tickets;
create policy profile_boost_message_tickets_owner_update
  on public.profile_boost_message_tickets
  for update to authenticated
  using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
revoke all on public.profile_boost_message_tickets from anon, authenticated;
grant select on public.profile_boost_message_tickets to authenticated;

-- Purchased boosts add one ticket each. Membership-based 30-minute boosts
-- continue using their existing function and do not create paid message tickets.
create or replace function public.activate_my_purchased_profile_boost(
  p_item_code text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := now();
  v_end timestamptz;
  v_remaining integer;
  v_boost_id uuid;
  v_message_tickets integer;
begin
  if v_uid is null then
    raise exception 'Authentication required.';
  end if;
  if p_item_code not in ('profile_boost_24h','profile_boost_3') then
    raise exception 'Choose a purchased Profile Boost item.';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text, 24));

  if p_item_code = 'profile_boost_3' then
    update public.coin_store_inventory
       set quantity = quantity - 1, updated_at = v_now
     where user_id = v_uid
       and item_code = 'profile_boost_3'
       and quantity > 0
     returning quantity into v_remaining;

    if not found then
      raise exception 'You do not have an unused 3 Profile Boost pack.';
    end if;

    insert into public.coin_store_inventory(user_id,item_code,quantity,updated_at)
    values(v_uid,'profile_boost_24h',3,v_now)
    on conflict(user_id,item_code) do update
      set quantity = public.coin_store_inventory.quantity + excluded.quantity,
          updated_at = excluded.updated_at;
  end if;

  update public.coin_store_inventory
     set quantity = quantity - 1, updated_at = v_now
   where user_id = v_uid
     and item_code = 'profile_boost_24h'
     and quantity > 0
   returning quantity into v_remaining;

  if not found then
    raise exception 'You do not have an unused 24-hour Profile Boost.';
  end if;

  v_end := v_now + interval '24 hours';
  insert into public.profile_boosts(user_id,starts_at,ends_at)
  values(v_uid,v_now,v_end)
  returning id into v_boost_id;

  insert into public.profile_boost_message_tickets(user_id,profile_boost_id,expires_at)
  values(v_uid,v_boost_id,v_end);

  select count(*)::integer into v_message_tickets
  from public.profile_boost_message_tickets t
  where t.user_id = v_uid and t.used_at is null and t.expires_at > v_now;

  return pg_catalog.jsonb_build_object(
    'success',true,
    'starts_at',v_now,
    'ends_at',v_end,
    'remaining_24h_boosts',v_remaining,
    'remaining_message_tickets',v_message_tickets
  );
end;
$$;
revoke all on function public.activate_my_purchased_profile_boost(text) from public, anon;
grant execute on function public.activate_my_purchased_profile_boost(text) to authenticated;

-- Permit the two participants to continue chatting after the boost-funded
-- first message, even if they have not mutually liked each other.
drop policy if exists messages_boost_initiated_conversation_insert on public.messages;
create policy messages_boost_initiated_conversation_insert
  on public.messages
  for insert to authenticated
  with check (
    sender_id = (select auth.uid())
    and exists (
      select 1
      from public.profile_boost_message_tickets t
      where t.used_at is not null
        and (
          (t.user_id = sender_id and t.recipient_id = receiver_id)
          or
          (t.user_id = receiver_id and t.recipient_id = sender_id)
        )
    )
  );

-- Keep the privileged write helper in a non-exposed schema. The public RPC
-- remains SECURITY INVOKER and delegates only after the helper validates auth.uid().
create schema if not exists app_private;
revoke all on schema app_private from public, anon;
grant usage on schema app_private to authenticated;

create or replace function app_private.send_discover_first_message(
  p_target_user_id uuid,
  p_body text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_ticket_id uuid;
  v_message_id uuid;
  v_remaining integer;
  v_existing_message_id uuid;
begin
  if v_uid is null then raise exception 'Sign in to send a first message'; end if;
  if p_target_user_id is null or p_target_user_id = v_uid then
    raise exception 'Choose another member to message';
  end if;
  if p_body is null or length(pg_catalog.btrim(p_body)) = 0 then
    raise exception 'Write a message before sending';
  end if;
  if length(p_body) > 2000 then raise exception 'Messages can contain up to 2,000 characters'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 120 then
    raise exception 'A valid message request reference is required';
  end if;
  if not public.can_interact_with_member(p_target_user_id) then
    raise exception 'This profile is unavailable';
  end if;

  select t.message_id into v_existing_message_id
  from public.profile_boost_message_tickets t
  where t.user_id = v_uid and t.request_key = p_idempotency_key
  limit 1;
  if v_existing_message_id is not null then
    select count(*)::integer into v_remaining
    from public.profile_boost_message_tickets t
    where t.user_id = v_uid and t.used_at is null and t.expires_at > now();
    return pg_catalog.jsonb_build_object(
      'sent',true,'already_processed',true,
      'message_id',v_existing_message_id,'remaining_tickets',v_remaining
    );
  end if;

  if exists (
    select 1 from public.profile_boost_message_tickets t
    where t.user_id = v_uid and t.recipient_id = p_target_user_id
  ) then
    raise exception 'You already used a first-message ticket for this member. Continue in Chats.';
  end if;

  select t.id into v_ticket_id
  from public.profile_boost_message_tickets t
  where t.user_id = v_uid
    and t.used_at is null
    and t.expires_at > now()
  order by t.created_at, t.id
  for update skip locked
  limit 1;

  if v_ticket_id is null then
    raise exception 'NO_BOOST_MESSAGE_TICKETS: Activate another purchased Profile Boost to message someone new.';
  end if;

  update public.profile_boost_message_tickets
  set recipient_id = p_target_user_id,
      request_key = p_idempotency_key,
      used_at = now()
  where id = v_ticket_id and user_id = v_uid and used_at is null;

  insert into public.messages(sender_id,receiver_id,body)
  values(v_uid,p_target_user_id,pg_catalog.btrim(p_body))
  returning id into v_message_id;

  update public.profile_boost_message_tickets
  set message_id = v_message_id
  where id = v_ticket_id;

  select count(*)::integer into v_remaining
  from public.profile_boost_message_tickets t
  where t.user_id = v_uid and t.used_at is null and t.expires_at > now();

  return pg_catalog.jsonb_build_object(
    'sent',true,'already_processed',false,
    'message_id',v_message_id,'remaining_tickets',v_remaining
  );
end;
$$;
revoke all on function app_private.send_discover_first_message(uuid,text,text) from public, anon;
grant execute on function app_private.send_discover_first_message(uuid,text,text) to authenticated;

create or replace function public.send_discover_first_message(
  p_target_user_id uuid,
  p_body text,
  p_idempotency_key text
) returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select app_private.send_discover_first_message(
    p_target_user_id,p_body,p_idempotency_key
  );
$$;
revoke all on function public.send_discover_first_message(uuid,text,text) from public, anon;
grant execute on function public.send_discover_first_message(uuid,text,text) to authenticated;
