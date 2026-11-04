-- Harden coin spending against duplicate requests and cross-item idempotency-key reuse.
-- Staged on the GitHub test branch only. Do not apply to production before PostgreSQL tests.

create or replace function public.coin_spend(
  p_item_code text,
  p_quantity integer default 1,
  p_idempotency_key text default null
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_cost integer;
  v_balance integer;
  v_kind text;
  v_tier text;
  v_description text;
  v_existing_amount integer;
  v_existing_type text;
  v_existing_description text;
begin
  if v_uid is null then raise exception 'Sign in to continue'; end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 30 then
    raise exception 'Invalid quantity';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 120 then
    raise exception 'A valid purchase reference is required';
  end if;

  if p_item_code in ('plus_30d','quarterly_90d','annual_365d') then
    v_kind := 'membership_debit';
    select cost,tier into v_cost,v_tier
    from (values
      ('plus_30d',300,'plus',30),
      ('quarterly_90d',800,'quarterly',90),
      ('annual_365d',2800,'annual',365)
    ) as t(code,cost,tier,days)
    where code=p_item_code;
    if p_quantity <> 1 then raise exception 'Memberships can only be purchased one at a time'; end if;
    v_description := 'Purchased '||p_item_code;
  else
    v_kind := 'store_debit';
    select cost into v_cost
    from (values
      ('profile_boost_24h',40),('profile_boost_3',100),('super_like_1',10),('super_like_5',45),
      ('extra_likes_10',30),('extra_likes_30',75),('priority_7d',100),('priority_30d',250),
      ('decorative_badge',100),('animated_effect',150)
    ) as items(code,cost)
    where code=p_item_code;
    if v_cost is null then raise exception 'Unknown store item'; end if;
    v_description := 'Purchased '||p_item_code||' (quantity '||p_quantity::text||')';
  end if;

  v_cost := v_cost * p_quantity;

  -- The wallet row is the serialization point for every spend by this member.
  insert into public.coin_wallets(user_id) values(v_uid)
  on conflict(user_id) do nothing;
  select balance into v_balance
  from public.coin_wallets
  where user_id=v_uid
  for update;

  -- Recheck only after acquiring the wallet lock. A concurrent retry now sees
  -- the committed ledger row and cannot deduct or fulfil the same request twice.
  select amount,entry_type,description
  into v_existing_amount,v_existing_type,v_existing_description
  from public.coin_ledger
  where user_id=v_uid and idempotency_key=p_idempotency_key;

  if found then
    if v_existing_amount <> -v_cost
      or v_existing_type <> v_kind
      or (
        v_existing_description <> v_description
        and not (p_quantity=1 and v_existing_description='Purchased '||p_item_code)
      ) then
      raise exception 'This purchase reference was already used for a different item or quantity.';
    end if;
    return v_balance;
  end if;

  if v_balance < v_cost then raise exception 'Not enough coins'; end if;

  update public.coin_wallets
  set balance=balance-v_cost,updated_at=now()
  where user_id=v_uid
  returning balance into v_balance;

  insert into public.coin_ledger(
    user_id,amount,balance_after,entry_type,idempotency_key,description
  ) values(
    v_uid,-v_cost,v_balance,v_kind,p_idempotency_key,v_description
  );

  if v_kind='membership_debit' then
    -- Keep the existing expiry when active; start from now when expired or absent.
    insert into public.match_plus_memberships(user_id,tier,started_at,expires_at)
    values(v_uid,v_tier,now(),now()+make_interval(days=>case p_item_code
      when 'plus_30d' then 30 when 'quarterly_90d' then 90 else 365 end))
    on conflict(user_id) do update
    set tier=excluded.tier,
        started_at=case when public.match_plus_memberships.expires_at>now()
          then public.match_plus_memberships.started_at else now() end,
        expires_at=greatest(public.match_plus_memberships.expires_at,now())
          + make_interval(days=>case p_item_code
            when 'plus_30d' then 30 when 'quarterly_90d' then 90 else 365 end),
        updated_at=now();
  else
    insert into public.coin_store_purchases(user_id,item_code,quantity,coins_spent)
    values(v_uid,p_item_code,p_quantity,v_cost);
    insert into public.coin_store_inventory(user_id,item_code,quantity)
    values(v_uid,p_item_code,p_quantity)
    on conflict(user_id,item_code) do update
    set quantity=public.coin_store_inventory.quantity+excluded.quantity,updated_at=now();
  end if;

  return v_balance;
end;
$$;

-- Membership-level advisory locking also serializes first-time purchases when
-- the member has no existing membership row to SELECT ... FOR UPDATE.
create or replace function public.coin_buy_membership(
  p_tier text,
  p_idempotency_key text
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_cost integer;
  v_current_tier text;
  v_current_expiry timestamptz;
  v_new_rank integer;
  v_current_rank integer;
  v_existing_amount integer;
  v_existing_type text;
  v_existing_description text;
  v_balance integer;
begin
  if v_uid is null then raise exception 'Sign in to continue'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 120 then
    raise exception 'A valid purchase reference is required';
  end if;

  v_code := case p_tier
    when 'plus' then 'plus_30d'
    when 'quarterly' then 'quarterly_90d'
    when 'annual' then 'annual_365d'
    else null
  end;
  if v_code is null then raise exception 'Invalid Match membership tier'; end if;

  v_cost := case p_tier when 'plus' then 300 when 'quarterly' then 800 else 2800 end;

  -- One membership transition per member at a time, including first purchase.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_uid::text, 4202)
  );

  select amount,entry_type,description
  into v_existing_amount,v_existing_type,v_existing_description
  from public.coin_ledger
  where user_id=v_uid and idempotency_key=p_idempotency_key;

  if found then
    if v_existing_amount <> -v_cost
      or v_existing_type <> 'membership_debit'
      or v_existing_description <> 'Purchased '||v_code then
      raise exception 'This purchase reference was already used for a different membership transaction.';
    end if;
    select balance into v_balance from public.coin_wallets where user_id=v_uid;
    return coalesce(v_balance,0);
  end if;

  select tier,expires_at
  into v_current_tier,v_current_expiry
  from public.match_plus_memberships
  where user_id=v_uid
  for update;

  v_new_rank := case p_tier when 'plus' then 1 when 'quarterly' then 2 else 3 end;
  v_current_rank := case v_current_tier when 'plus' then 1 when 'quarterly' then 2 when 'annual' then 3 else 0 end;

  if v_current_expiry>now() and v_current_rank>v_new_rank then
    raise exception 'Your current Match Plus tier is higher. Wait until it expires or choose an upgrade.';
  end if;

  return public.coin_spend(v_code,1,p_idempotency_key);
end;
$$;

revoke all on function public.coin_spend(text,integer,text) from public,anon,authenticated;
revoke all on function public.coin_buy_membership(text,text) from public,anon;
grant execute on function public.coin_buy_membership(text,text) to authenticated;
