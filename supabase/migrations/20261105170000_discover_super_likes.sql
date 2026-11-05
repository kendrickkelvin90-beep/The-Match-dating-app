-- Secure Super Like redemption from Discover.
-- Each Super Like consumes one owned inventory unit and also records a normal like,
-- so the existing mutual-like/matching system continues to work.
create table if not exists public.super_likes (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  idempotency_key text not null,
  created_at timestamptz not null default now(),
  constraint super_likes_not_self check (sender_id <> recipient_id),
  constraint super_likes_sender_request_unique unique(sender_id, idempotency_key)
);
create index if not exists super_likes_recipient_created_idx
  on public.super_likes(recipient_id, created_at desc);
alter table public.super_likes enable row level security;
drop policy if exists super_likes_participant_read on public.super_likes;
create policy super_likes_participant_read on public.super_likes
  for select to authenticated
  using (sender_id = (select auth.uid()) or recipient_id = (select auth.uid()));
revoke all on public.super_likes from anon, authenticated;
grant select on public.super_likes to authenticated;

create or replace function public.send_super_like(
  p_target_user_id uuid,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_item_code text;
  v_quantity integer;
  v_remaining integer;
  v_matched boolean := false;
begin
  if v_uid is null then raise exception 'Sign in to send a Super Like'; end if;
  if p_target_user_id is null or p_target_user_id = v_uid then
    raise exception 'Choose another member to Super Like';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 120 then
    raise exception 'A valid request reference is required';
  end if;
  if not exists(select 1 from public.profiles p where p.id = p_target_user_id) then
    raise exception 'This profile is no longer available';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_uid::text, 7319)
  );

  if exists (
    select 1 from public.super_likes s
    where s.sender_id = v_uid and s.idempotency_key = p_idempotency_key
  ) then
    select coalesce(sum(i.quantity),0)::integer into v_remaining
    from public.coin_store_inventory i
    where i.user_id = v_uid and i.item_code in ('super_like_1','super_like_5');
    select exists(select 1 from public.likes l
      where l.liker_id = p_target_user_id and l.liked_id = v_uid) into v_matched;
    return jsonb_build_object('remaining',v_remaining,'matched',v_matched,'already_processed',true);
  end if;

  if exists(select 1 from public.likes l
    where l.liker_id = v_uid and l.liked_id = p_target_user_id) then
    raise exception 'You have already liked this member';
  end if;

  -- Consume one unit from whichever Super Like pack the member owns.
  select i.item_code, i.quantity into v_item_code, v_quantity
  from public.coin_store_inventory i
  where i.user_id = v_uid
    and i.item_code in ('super_like_1','super_like_5')
    and i.quantity > 0
  order by case i.item_code when 'super_like_1' then 0 else 1 end
  limit 1
  for update;

  if v_item_code is null then
    raise exception 'NO_SUPER_LIKES: Buy Super Likes from the Coin Store first';
  end if;

  update public.coin_store_inventory
  set quantity = quantity - 1, updated_at = now()
  where user_id = v_uid and item_code = v_item_code
  returning quantity into v_quantity;

  insert into public.likes(liker_id, liked_id)
  values(v_uid, p_target_user_id);

  insert into public.super_likes(sender_id, recipient_id, idempotency_key)
  values(v_uid, p_target_user_id, p_idempotency_key);

  insert into public.notifications(user_id, type, title, body)
  values(
    p_target_user_id,
    'like',
    'You received a Super Like',
    'Someone sent you a Super Like. Open The Match to see who it was.'
  );

  select coalesce(sum(i.quantity),0)::integer into v_remaining
  from public.coin_store_inventory i
  where i.user_id = v_uid and i.item_code in ('super_like_1','super_like_5');

  select exists(select 1 from public.likes l
    where l.liker_id = p_target_user_id and l.liked_id = v_uid) into v_matched;

  return jsonb_build_object('remaining',v_remaining,'matched',v_matched,'already_processed',false);
end;
$$;
revoke all on function public.send_super_like(uuid,text) from public, anon;
grant execute on function public.send_super_like(uuid,text) to authenticated;
