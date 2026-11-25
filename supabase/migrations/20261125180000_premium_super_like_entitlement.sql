-- Premium Super Likes: no coin debit for active Premium; coins remain required for everyone else.
create or replace function public.send_super_like(p_target_user_id uuid, p_idempotency_key text)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_item_code text;
  v_quantity integer;
  v_remaining integer;
  v_matched boolean := false;
  v_is_premium boolean := false;
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
  if public.member_can_interact_with_discover_profile(p_target_user_id) is not true then
    raise exception 'Complete your private dating orientation before interacting with this profile';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text, 7319));
  select public.is_match_premium(v_uid) into v_is_premium;

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

  if not v_is_premium then
    select i.item_code, i.quantity into v_item_code, v_quantity
    from public.coin_store_inventory i
    where i.user_id = v_uid
      and i.item_code in ('super_like_1','super_like_5')
      and i.quantity > 0
    order by case i.item_code when 'super_like_1' then 0 else 1 end
    limit 1 for update;

    if v_item_code is null then
      raise exception 'NO_SUPER_LIKES: Buy Super Likes from the Coin Store first';
    end if;

    update public.coin_store_inventory
    set quantity = quantity - 1, updated_at = now()
    where user_id = v_uid and item_code = v_item_code
    returning quantity into v_quantity;
  end if;

  insert into public.likes(liker_id, liked_id) values(v_uid, p_target_user_id);
  insert into public.super_likes(sender_id, recipient_id, idempotency_key)
  values(v_uid, p_target_user_id, p_idempotency_key);
  insert into public.notifications(user_id, type, title, body)
  values(p_target_user_id, 'like', 'You received a Super Like',
    'Someone sent you a Super Like. Open The Match to see who it was.');

  select coalesce(sum(i.quantity),0)::integer into v_remaining
  from public.coin_store_inventory i
  where i.user_id = v_uid and i.item_code in ('super_like_1','super_like_5');
  select exists(select 1 from public.likes l
    where l.liker_id = p_target_user_id and l.liked_id = v_uid) into v_matched;

  return jsonb_build_object('remaining',v_remaining,'matched',v_matched,
    'already_processed',false,'premium_used',v_is_premium);
end;
$function$;