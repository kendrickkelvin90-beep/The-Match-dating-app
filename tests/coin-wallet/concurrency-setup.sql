-- Test-only delay triggers force overlap between separate PostgreSQL sessions.
create or replace function public.test_delay_membership_ledger()
returns trigger language plpgsql
as $$
begin
  if new.entry_type='membership_debit' then perform pg_sleep(1); end if;
  return new;
end;
$$;
create trigger test_delay_membership_ledger
before insert on public.coin_ledger
for each row execute function public.test_delay_membership_ledger();

create or replace function public.test_delay_gift_insert()
returns trigger language plpgsql
as $$
begin
  perform pg_sleep(1);
  return new;
end;
$$;
create trigger test_delay_gift_insert
before insert on public.member_gifts
for each row execute function public.test_delay_gift_insert();

insert into public.coin_wallets(user_id,balance) values
 ('66666666-6666-4666-8666-666666666666',1000),
 ('77777777-7777-4777-8777-777777777777',5000),
 ('88888888-8888-4888-8888-888888888888',100)
on conflict(user_id) do update set balance=excluded.balance;
