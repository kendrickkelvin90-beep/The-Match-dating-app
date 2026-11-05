-- Fulfil purchased Profile Boost inventory independently of Match Plus cooldowns.
-- A 3-boost pack is converted into three 24-hour activations: one starts now
-- and the two remaining activations are retained as individual inventory units.
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

    -- Convert the pack into two remaining single-use 24-hour boosts.
    insert into public.coin_store_inventory(user_id,item_code,quantity,updated_at)
    values(v_uid,'profile_boost_24h',2,v_now)
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
  values(v_uid,v_now,v_end);

  return pg_catalog.jsonb_build_object(
    'success',true,
    'starts_at',v_now,
    'ends_at',v_end,
    'remaining_24h_boosts',v_remaining
  );
end;
$$;

revoke all on function public.activate_my_purchased_profile_boost(text) from public, anon;
grant execute on function public.activate_my_purchased_profile_boost(text) to authenticated;
