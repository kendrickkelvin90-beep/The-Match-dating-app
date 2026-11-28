-- Permanent Match Coin profile-effect ownership and member-controlled activation.
-- One animated_effect purchase unlocks the selectable visual effects for the member.
begin;

create table if not exists public.member_profile_effects (
  user_id uuid primary key references auth.users(id) on delete cascade,
  effect_code text not null
    check (effect_code in ('sparkle','glow','hearts','shimmer')),
  activated_at timestamptz not null default now()
);

alter table public.member_profile_effects enable row level security;
revoke all on public.member_profile_effects from anon, authenticated;
grant select on public.member_profile_effects to authenticated;

drop policy if exists member_profile_effects_active_read on public.member_profile_effects;
create policy member_profile_effects_active_read
  on public.member_profile_effects for select to authenticated
  using (true);

-- Animated Profile Effect is a one-time permanent unlock. Preserve safe retries
-- by returning the prior wallet balance for the same idempotency key.
create or replace function public.coin_buy_store_item(
  p_item_code text,
  p_idempotency_key text
) returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_balance integer;
begin
  if v_uid is null then raise exception 'Sign in to continue'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 120 then
    raise exception 'A valid purchase reference is required';
  end if;

  if p_item_code = 'animated_effect' then
    if exists (
      select 1 from public.coin_ledger
      where user_id=v_uid and idempotency_key=p_idempotency_key
    ) then
      select balance into v_balance from public.coin_wallets where user_id=v_uid;
      return coalesce(v_balance,0);
    end if;
    if exists (
      select 1 from public.coin_store_inventory
      where user_id=v_uid and item_code='animated_effect' and quantity>0
    ) then
      raise exception 'You already own the permanent Animated Profile Effect unlock.';
    end if;
  end if;

  if p_item_code not in ('super_like_1','super_like_5','extra_likes_10','extra_likes_30',
    'profile_boost_24h','profile_boost_3','priority_7d','priority_30d',
    'decorative_badge','animated_effect') then
    raise exception 'This store item is not available for purchase';
  end if;

  return public.coin_spend(p_item_code,1,p_idempotency_key);
end;
$function$;

revoke all on function public.coin_buy_store_item(text,text) from public,anon;
grant execute on function public.coin_buy_store_item(text,text) to authenticated;

create or replace function public.set_my_profile_effect(
  p_effect_code text,
  p_active boolean
) returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_owned integer;
begin
  if v_uid is null then
    raise exception 'Please sign in to manage your profile effect.';
  end if;
  if p_effect_code is null or p_effect_code not in ('sparkle','glow','hearts','shimmer') then
    raise exception 'Choose a valid profile effect.';
  end if;
  if p_active is null then
    raise exception 'Choose whether to activate or deactivate your effect.';
  end if;

  if p_active then
    select coalesce(quantity,0) into v_owned
    from public.coin_store_inventory
    where user_id=v_uid and item_code='animated_effect';

    if coalesce(v_owned,0)<1 then
      raise exception 'Purchase the Animated Profile Effect before activating it.';
    end if;

    insert into public.member_profile_effects(user_id,effect_code,activated_at)
    values(v_uid,p_effect_code,now())
    on conflict(user_id) do update
      set effect_code=excluded.effect_code,
          activated_at=excluded.activated_at;
  else
    delete from public.member_profile_effects
    where user_id=v_uid and effect_code=p_effect_code;
  end if;

  return p_effect_code;
end;
$function$;

create or replace function public.get_active_profile_effects(p_user_ids uuid[])
returns table(user_id uuid,effect_code text)
language sql
stable
security invoker
set search_path = ''
as $function$
  select e.user_id,e.effect_code
  from public.member_profile_effects e
  where e.user_id = any(coalesce(p_user_ids,array[]::uuid[]))
  limit 100;
$function$;

revoke all on function public.set_my_profile_effect(text,boolean) from public,anon;
grant execute on function public.set_my_profile_effect(text,boolean) to authenticated;
revoke all on function public.get_active_profile_effects(uuid[]) from public,anon;
grant execute on function public.get_active_profile_effects(uuid[]) to authenticated;

comment on table public.member_profile_effects is
  'One active visual profile effect per member. Ownership is granted by the animated_effect Match Coin store inventory item.';
comment on function public.get_active_profile_effects(uuid[]) is
  'Returns selected profile effects for authenticated members; intended for profiles the caller is already allowed to view.';

commit;
