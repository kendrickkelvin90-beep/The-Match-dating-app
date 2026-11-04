-- Virtual gifts: secure, auditable coin transfers and redemption.
alter table public.coin_ledger drop constraint if exists coin_ledger_entry_type_check;
alter table public.coin_ledger add constraint coin_ledger_entry_type_check
  check (entry_type in ('purchase_credit','store_debit','membership_debit','annual_bonus','admin_adjustment','reversal','gift_send','gift_redeem'));

create table if not exists public.gift_catalog (
  code text primary key,
  name text not null,
  emoji text not null,
  send_cost integer not null check (send_cost > 0),
  redeem_coins integer not null check (redeem_coins >= 0 and redeem_coins <= send_cost),
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);
insert into public.gift_catalog(code,name,emoji,send_cost,redeem_coins,sort_order) values
 ('rose','Rose','🌹',10,8,1),
 ('star','Star','⭐',20,16,2),
 ('heart','Heart','❤️',25,20,3),
 ('crown','Crown','👑',50,40,4),
 ('premium','Premium gift','💎',100,80,5),
 ('surprise','Surprise gift','🎁',150,120,6)
on conflict(code) do update set name=excluded.name,emoji=excluded.emoji,send_cost=excluded.send_cost,redeem_coins=excluded.redeem_coins,sort_order=excluded.sort_order;

create table if not exists public.member_gifts (
 id uuid primary key default gen_random_uuid(),
 sender_id uuid not null references auth.users(id) on delete restrict,
 recipient_id uuid not null references auth.users(id) on delete restrict,
 gift_code text not null references public.gift_catalog(code),
 send_cost integer not null check(send_cost > 0),
 redeem_coins integer not null check(redeem_coins >= 0 and redeem_coins <= send_cost),
 message text check(message is null or char_length(message) <= 160),
 created_at timestamptz not null default now(),
 redeemed_at timestamptz,
 redemption_ledger_id uuid references public.coin_ledger(id),
 check(sender_id <> recipient_id)
);
create index if not exists member_gifts_recipient_created_idx on public.member_gifts(recipient_id,created_at desc);
create index if not exists member_gifts_sender_created_idx on public.member_gifts(sender_id,created_at desc);
alter table public.gift_catalog enable row level security;
alter table public.member_gifts enable row level security;
revoke all on public.gift_catalog,public.member_gifts from anon,authenticated;
grant select on public.gift_catalog,public.member_gifts to authenticated;
create policy gift_catalog_active_read on public.gift_catalog for select to authenticated using(active);
create policy member_gifts_participant_read on public.member_gifts for select to authenticated using(auth.uid()=sender_id or auth.uid()=recipient_id);

create or replace function public.send_member_gift(p_recipient_id uuid,p_gift_code text,p_message text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_sender uuid:=auth.uid(); v_gift public.gift_catalog%rowtype; v_balance integer; v_id uuid;
begin
 if v_sender is null then raise exception 'Please sign in.'; end if;
 if p_recipient_id is null or p_recipient_id=v_sender then raise exception 'Choose another member.'; end if;
 if not public.can_interact_with_member(p_recipient_id) then raise exception 'This conversation is unavailable.'; end if;
 select * into v_gift from public.gift_catalog where code=p_gift_code and active for share;
 if not found then raise exception 'This gift is unavailable.'; end if;
 if p_message is not null and char_length(p_message)>160 then raise exception 'Gift message is too long.'; end if;
 insert into public.coin_wallets(user_id,balance) values(v_sender,0) on conflict(user_id) do nothing;
 select balance into v_balance from public.coin_wallets where user_id=v_sender for update;
 if v_balance < v_gift.send_cost then raise exception 'Not enough coins in your wallet.'; end if;
 update public.coin_wallets set balance=balance-v_gift.send_cost,updated_at=now() where user_id=v_sender returning balance into v_balance;
 insert into public.member_gifts(sender_id,recipient_id,gift_code,send_cost,redeem_coins,message)
 values(v_sender,p_recipient_id,v_gift.code,v_gift.send_cost,v_gift.redeem_coins,nullif(btrim(p_message),'')) returning id into v_id;
 insert into public.coin_ledger(user_id,amount,balance_after,entry_type,reference_id,idempotency_key,description)
 values(v_sender,-v_gift.send_cost,v_balance,'gift_send',v_id,'gift-send:'||v_id,'Sent '||v_gift.name);
 return v_id;
end $$;
revoke all on function public.send_member_gift(uuid,text,text) from public,anon;
grant execute on function public.send_member_gift(uuid,text,text) to authenticated;

create or replace function public.redeem_member_gift(p_gift_id uuid)
returns integer language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid(); v_gift public.member_gifts%rowtype; v_balance integer; v_ledger uuid;
begin
 if v_user is null then raise exception 'Please sign in.'; end if;
 select * into v_gift from public.member_gifts where id=p_gift_id and recipient_id=v_user for update;
 if not found then raise exception 'Gift not found in your collection.'; end if;
 if v_gift.redeemed_at is not null then raise exception 'This gift has already been redeemed.'; end if;
 if v_gift.redeem_coins<=0 then raise exception 'This gift cannot be redeemed.'; end if;
 insert into public.coin_wallets(user_id,balance) values(v_user,0) on conflict(user_id) do nothing;
 update public.coin_wallets set balance=balance+v_gift.redeem_coins,updated_at=now() where user_id=v_user returning balance into v_balance;
 insert into public.coin_ledger(user_id,amount,balance_after,entry_type,reference_id,idempotency_key,description)
 values(v_user,v_gift.redeem_coins,v_balance,'gift_redeem',v_gift.id,'gift-redeem:'||v_gift.id,'Redeemed received gift') returning id into v_ledger;
 update public.member_gifts set redeemed_at=now(),redemption_ledger_id=v_ledger where id=v_gift.id;
 return v_balance;
end $$;
revoke all on function public.redeem_member_gift(uuid) from public,anon;
grant execute on function public.redeem_member_gift(uuid) to authenticated;


-- Admin-only gift catalogue management. Every write is re-authorized in PostgreSQL.
create or replace function public.admin_save_gift(
 p_code text,p_name text,p_emoji text,p_send_cost integer,p_redeem_coins integer,p_sort_order integer default 0
) returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_match_admin() then raise exception 'Admin access required.'; end if;
 if p_code !~ '^[a-z0-9_]{2,32}$' or length(btrim(p_name)) not between 2 and 60
   or length(btrim(p_emoji)) not between 1 and 12
   or p_send_cost not between 1 and 100000
   or p_redeem_coins not between 0 and p_send_cost
   or p_sort_order not between 0 and 1000 then
   raise exception 'Please check the gift details and coin values.';
 end if;
 insert into public.gift_catalog(code,name,emoji,send_cost,redeem_coins,sort_order,active)
 values(p_code,btrim(p_name),btrim(p_emoji),p_send_cost,p_redeem_coins,p_sort_order,true)
 on conflict(code) do update set name=excluded.name,emoji=excluded.emoji,
 send_cost=excluded.send_cost,redeem_coins=excluded.redeem_coins,sort_order=excluded.sort_order;
end $$;
revoke all on function public.admin_save_gift(text,text,text,integer,integer,integer) from public,anon;
grant execute on function public.admin_save_gift(text,text,text,integer,integer,integer) to authenticated;

create or replace function public.admin_set_gift_active(p_code text,p_active boolean)
returns void language plpgsql security definer set search_path='' as $$
begin
 if not public.is_match_admin() then raise exception 'Admin access required.'; end if;
 update public.gift_catalog set active=p_active where code=p_code;
 if not found then raise exception 'Gift not found.'; end if;
end $$;
revoke all on function public.admin_set_gift_active(text,boolean) from public,anon;
grant execute on function public.admin_set_gift_active(text,boolean) to authenticated;

drop function if exists public.admin_gift_activity(integer);
create function public.admin_gift_activity(p_limit integer default 100)
returns table(gift_id uuid,sender_id uuid,recipient_id uuid,gift_code text,send_cost integer,redeem_coins integer,created_at timestamptz,redeemed_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
 if not public.is_match_admin() then raise exception 'Admin access required.'; end if;
 return query select g.id,g.sender_id,g.recipient_id,g.gift_code,g.send_cost,g.redeem_coins,g.created_at,g.redeemed_at
 from public.member_gifts g order by g.created_at desc limit greatest(1,least(coalesce(p_limit,100),200));
end $$;
revoke all on function public.admin_gift_activity(integer) from public,anon;
grant execute on function public.admin_gift_activity(integer) to authenticated;
