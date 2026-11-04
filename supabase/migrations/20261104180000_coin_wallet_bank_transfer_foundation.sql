-- The Match coin wallet and Match Plus foundation.
-- This migration is staged for review only; do not apply to production until tested.
create table if not exists public.coin_wallets (
  user_id uuid primary key references auth.users(id) on delete cascade,
  balance integer not null default 0 check (balance >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.coin_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  amount integer not null check (amount <> 0),
  balance_after integer not null check (balance_after >= 0),
  entry_type text not null check (entry_type in ('purchase_credit','store_debit','membership_debit','annual_bonus','admin_adjustment','reversal')),
  reference_id uuid,
  idempotency_key text not null,
  description text not null,
  created_at timestamptz not null default now(),
  unique(user_id, idempotency_key)
);
create index if not exists coin_ledger_user_created_idx on public.coin_ledger(user_id, created_at desc);

create table if not exists public.coin_purchase_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  package_code text not null check (package_code in ('starter_50','popular_120','value_260','bundle_700','ultimate_1500')),
  coins integer not null check (coins in (50,120,260,700,1500)),
  amount_ngn integer not null check (amount_ngn in (1000,2000,4000,10000,20000)),
  sender_name text not null check (length(trim(sender_name)) between 2 and 120),
  transfer_reference text not null check (length(trim(transfer_reference)) between 3 and 160),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique(transfer_reference)
);

create table if not exists public.match_plus_memberships (
  user_id uuid primary key references auth.users(id) on delete cascade,
  tier text not null check (tier in ('plus','quarterly','annual')),
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  last_bonus_period date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.coin_store_inventory (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_code text not null,
  quantity integer not null default 0 check (quantity >= 0),
  updated_at timestamptz not null default now(),
  primary key(user_id,item_code)
);

create table if not exists public.coin_store_purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  item_code text not null,
  quantity integer not null check (quantity > 0),
  coins_spent integer not null check (coins_spent > 0),
  created_at timestamptz not null default now()
);

alter table public.coin_wallets enable row level security;
alter table public.coin_ledger enable row level security;
alter table public.coin_purchase_requests enable row level security;
alter table public.match_plus_memberships enable row level security;
alter table public.coin_store_inventory enable row level security;
alter table public.coin_store_purchases enable row level security;

drop policy if exists coin_wallets_owner_read on public.coin_wallets;
create policy coin_wallets_owner_read on public.coin_wallets for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists coin_ledger_owner_read on public.coin_ledger;
create policy coin_ledger_owner_read on public.coin_ledger for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists coin_requests_owner_read on public.coin_purchase_requests;
create policy coin_requests_owner_read on public.coin_purchase_requests for select to authenticated using (user_id = (select auth.uid()) or exists(select 1 from public.app_admins a where a.user_id = (select auth.uid())));
drop policy if exists coin_plus_owner_read on public.match_plus_memberships;
create policy coin_plus_owner_read on public.match_plus_memberships for select to authenticated using (user_id = (select auth.uid()) or exists(select 1 from public.app_admins a where a.user_id = (select auth.uid())));
drop policy if exists coin_inventory_owner_read on public.coin_store_inventory;
create policy coin_inventory_owner_read on public.coin_store_inventory for select to authenticated using (user_id = (select auth.uid()));
drop policy if exists coin_store_purchases_owner_read on public.coin_store_purchases;
create policy coin_store_purchases_owner_read on public.coin_store_purchases for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.coin_wallets, public.coin_ledger, public.coin_purchase_requests, public.match_plus_memberships, public.coin_store_inventory, public.coin_store_purchases from anon, authenticated;
grant select on public.coin_wallets, public.coin_ledger, public.coin_purchase_requests, public.match_plus_memberships, public.coin_store_inventory, public.coin_store_purchases to authenticated;

create or replace function public.coin_is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists(select 1 from public.app_admins a where a.user_id = (select auth.uid()));
$$;
revoke all on function public.coin_is_admin() from public, anon;
grant execute on function public.coin_is_admin() to authenticated;

create or replace function public.coin_submit_purchase(
  p_package_code text, p_sender_name text, p_transfer_reference text
) returns uuid
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_coins integer; v_amount integer; v_id uuid; v_pending integer;
begin
  if v_uid is null then raise exception 'Sign in to continue'; end if;
  if length(trim(coalesce(p_sender_name,''))) not between 2 and 120 then raise exception 'Enter the sender name'; end if;
  if length(trim(coalesce(p_transfer_reference,''))) not between 3 and 160 then raise exception 'Enter the transfer reference'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_uid::text, 3));
  select count(*)::integer into v_pending
    from public.coin_purchase_requests
    where user_id=v_uid and status='pending';
  if v_pending >= 3 then raise exception 'You already have 3 coin transfer requests awaiting review. Please wait for an administrator to review them.'; end if;
  select coins, amount into v_coins, v_amount from (values
    ('starter_50',50,1000),('popular_120',120,2000),('value_260',260,4000),
    ('bundle_700',700,10000),('ultimate_1500',1500,20000)
  ) as packs(code,coins,amount) where code=p_package_code;
  if v_coins is null then raise exception 'Invalid coin package'; end if;
  insert into public.coin_purchase_requests(user_id,package_code,coins,amount_ngn,sender_name,transfer_reference)
  values(v_uid,p_package_code,v_coins,v_amount,trim(p_sender_name),upper(trim(p_transfer_reference)))
  returning id into v_id;
  insert into public.coin_wallets(user_id) values(v_uid) on conflict(user_id) do nothing;
  return v_id;
end;
$$;
revoke all on function public.coin_submit_purchase(text,text,text) from public, anon;
grant execute on function public.coin_submit_purchase(text,text,text) to authenticated;

create or replace function public.coin_admin_review_purchase(
  p_request_id uuid, p_decision text, p_reason text default null
) returns void
language plpgsql security definer set search_path = ''
as $$
declare v_req public.coin_purchase_requests%rowtype; v_balance integer; v_admin uuid := auth.uid();
begin
  if v_admin is null or not exists(select 1 from public.app_admins a where a.user_id=v_admin) then
    raise exception 'Administrator access required';
  end if;
  if p_decision is null or p_decision not in ('approved','rejected') then raise exception 'Invalid review decision'; end if;
  if p_decision='rejected' and length(trim(coalesce(p_reason,''))) < 3 then raise exception 'Enter a rejection reason'; end if;
  select * into v_req from public.coin_purchase_requests where id=p_request_id for update;
  if not found then raise exception 'Purchase request not found'; end if;
  if v_req.status <> 'pending' then raise exception 'This request has already been reviewed'; end if;
  update public.coin_purchase_requests set status=p_decision, admin_note=case when p_decision='rejected' then trim(p_reason) else null end, reviewed_by=v_admin, reviewed_at=now() where id=p_request_id;
  if p_decision='approved' then
    insert into public.coin_wallets(user_id) values(v_req.user_id) on conflict(user_id) do nothing;
    select balance into v_balance from public.coin_wallets where user_id=v_req.user_id for update;
    update public.coin_wallets set balance=balance+v_req.coins, updated_at=now() where user_id=v_req.user_id returning balance into v_balance;
    insert into public.coin_ledger(user_id,amount,balance_after,entry_type,reference_id,idempotency_key,description)
    values(v_req.user_id,v_req.coins,v_balance,'purchase_credit',v_req.id,'coin-purchase:'||v_req.id::text,'Coin package purchase approved');
  end if;
  insert into public.notifications(user_id,type,title,body)
  values(v_req.user_id,
    case when p_decision='approved' then 'coins_credited' else 'coin_purchase_rejected' end,
    case when p_decision='approved' then 'Coins added to your wallet' else 'Coin purchase not approved' end,
    case when p_decision='approved' then v_req.coins::text||' coins have been added to your wallet.' else 'Your coin purchase was not approved. Reason: '||trim(p_reason) end);
end;
$$;
revoke all on function public.coin_admin_review_purchase(uuid,text,text) from public, anon;
grant execute on function public.coin_admin_review_purchase(uuid,text,text) to authenticated;

create or replace function public.coin_spend(
  p_item_code text, p_quantity integer default 1, p_idempotency_key text default null
) returns integer
language plpgsql security definer set search_path = ''
as $$
declare v_uid uuid := auth.uid(); v_cost integer; v_balance integer; v_kind text; v_tier text; v_days integer; v_expiry timestamptz;
begin
  if v_uid is null then raise exception 'Sign in to continue'; end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 30 then raise exception 'Invalid quantity'; end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 120 then raise exception 'A valid purchase reference is required'; end if;
  if exists(select 1 from public.coin_ledger where user_id=v_uid and idempotency_key=p_idempotency_key) then
    select balance into v_balance from public.coin_wallets where user_id=v_uid;
    return coalesce(v_balance,0);
  end if;

  if p_item_code in ('plus_30d','quarterly_90d','annual_365d') then
    v_kind:='membership_debit';
    select cost,tier,days into v_cost,v_tier,v_days from (values
      ('plus_30d',300,'plus',30),('quarterly_90d',800,'quarterly',90),('annual_365d',2800,'annual',365)
    ) as t(code,cost,tier,days) where code=p_item_code;
    if p_quantity <> 1 then raise exception 'Memberships can only be purchased one at a time'; end if;
  else
    v_kind:='store_debit';
    select cost into v_cost from (values
      ('profile_boost_24h',40),('profile_boost_3',100),('super_like_1',10),('super_like_5',45),
      ('extra_likes_10',30),('extra_likes_30',75),('priority_7d',100),('priority_30d',250),
      ('decorative_badge',100),('animated_effect',150)
    ) as items(code,cost) where code=p_item_code;
    if v_cost is null then raise exception 'Unknown store item'; end if;
  end if;
  v_cost:=v_cost*p_quantity;
  insert into public.coin_wallets(user_id) values(v_uid) on conflict(user_id) do nothing;
  select balance into v_balance from public.coin_wallets where user_id=v_uid for update;
  if v_balance < v_cost then raise exception 'Not enough coins'; end if;
  update public.coin_wallets set balance=balance-v_cost,updated_at=now() where user_id=v_uid returning balance into v_balance;
  insert into public.coin_ledger(user_id,amount,balance_after,entry_type,idempotency_key,description)
  values(v_uid,-v_cost,v_balance,v_kind,p_idempotency_key,'Purchased '||p_item_code);
  if v_kind='membership_debit' then
    select greatest(coalesce(expires_at,now()),now()) into v_expiry from public.match_plus_memberships where user_id=v_uid for update;
    v_expiry:=coalesce(v_expiry,now()) + make_interval(days=>v_days);
    insert into public.match_plus_memberships(user_id,tier,started_at,expires_at)
    values(v_uid,v_tier,now(),v_expiry)
    on conflict(user_id) do update set tier=excluded.tier,expires_at=excluded.expires_at,updated_at=now();
  else
    insert into public.coin_store_purchases(user_id,item_code,quantity,coins_spent)
    values(v_uid,p_item_code,p_quantity,v_cost);
    insert into public.coin_store_inventory(user_id,item_code,quantity)
    values(v_uid,p_item_code,p_quantity)
    on conflict(user_id,item_code) do update set quantity=public.coin_store_inventory.quantity+excluded.quantity,updated_at=now();
  end if;
  return v_balance;
end;
$$;
-- Keep coin spending unavailable until every membership/store benefit has a tested
-- server-side fulfillment path. The UI also keeps these actions disabled.
revoke all on function public.coin_spend(text,integer,text) from public, anon, authenticated;

create or replace function public.coin_grant_annual_bonus()
returns integer language plpgsql security definer set search_path = ''
as $$
declare v_row record; v_balance integer; v_period date := (now() at time zone 'UTC')::date; v_count integer := 0; v_key text;
begin
  if not exists(select 1 from public.app_admins a where a.user_id=(select auth.uid())) then raise exception 'Administrator access required'; end if;
  for v_row in select user_id from public.match_plus_memberships where tier='annual' and expires_at>now()
    and (last_bonus_period is null or last_bonus_period <= v_period - 30)
    for update
  loop
    v_key:='annual-bonus:'||v_period::text;
    if not exists(select 1 from public.coin_ledger where user_id=v_row.user_id and idempotency_key=v_key) then
      insert into public.coin_wallets(user_id) values(v_row.user_id) on conflict(user_id) do nothing;
      select balance into v_balance from public.coin_wallets where user_id=v_row.user_id for update;
      update public.coin_wallets set balance=balance+50,updated_at=now() where user_id=v_row.user_id returning balance into v_balance;
      insert into public.coin_ledger(user_id,amount,balance_after,entry_type,idempotency_key,description)
      values(v_row.user_id,50,v_balance,'annual_bonus',v_key,'Match Annual 30-day coin reward');
      v_count:=v_count+1;
    end if;
    update public.match_plus_memberships set last_bonus_period=v_period,updated_at=now() where user_id=v_row.user_id;
  end loop;
  return v_count;
end;
$$;
revoke all on function public.coin_grant_annual_bonus() from public, anon;
grant execute on function public.coin_grant_annual_bonus() to authenticated;

comment on table public.coin_ledger is 'Append-only audit ledger; wallet balance is changed only by trusted RPCs.';
comment on table public.coin_purchase_requests is 'Manual bank-transfer requests; credits occur only after admin approval.';
