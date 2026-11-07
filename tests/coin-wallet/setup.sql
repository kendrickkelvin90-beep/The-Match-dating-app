-- Disposable PostgreSQL fixture for coin-wallet integration tests.
-- This database is created by GitHub Actions and contains no production data.
create extension if not exists pgcrypto;

do $roles$
begin
  if not exists(select 1 from pg_roles where rolname='anon') then execute 'create role anon nologin'; end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then execute 'create role authenticated nologin'; end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then execute 'create role service_role nologin'; end if;
end
$roles$;

create schema if not exists auth;
create table auth.users(id uuid primary key);
create or replace function auth.uid()
returns uuid language sql stable
as $$
  select nullif(pg_catalog.current_setting('request.jwt.claim.sub',true),'')::uuid;
$$;
grant usage on schema auth to anon,authenticated,service_role;
grant execute on function auth.uid() to public;

create table public.app_admins(
  user_id uuid primary key references auth.users(id) on delete cascade
);
create table public.notifications(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null,
  created_at timestamptz not null default now()
);

-- Minimal DM table and notification trigger used by the virtual-gift delivery migration.
create table public.messages(
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id),
  receiver_id uuid not null references auth.users(id),
  body text not null,
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  read_at timestamptz,
  unsent_at timestamptz
);
create or replace function public.notify_match_message()
returns trigger language plpgsql security definer set search_path=''
as $gift_test$
begin
  insert into public.notifications(user_id,type,title,body)
  values(new.receiver_id,'message','New message','A member sent you a message.');
  return new;
end;
$gift_test$;
create trigger trg_notify_match_message
after insert on public.messages
for each row execute function public.notify_match_message();

create publication supabase_realtime;

-- Existing application boost table used by the profile boost RPCs.
create table public.profile_boosts(
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  created_at timestamptz not null default now()
);

create or replace function public.is_match_admin()
returns boolean language sql stable security definer set search_path=''
as $$
  select exists(select 1 from public.app_admins a where a.user_id=(select auth.uid()));
$$;
create or replace function public.can_interact_with_member(p_member_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$
  select p_member_id is not null;
$$;

create or replace function public.test_assert(p_condition boolean,p_message text)
returns void language plpgsql
as $$
begin
  if p_condition is distinct from true then raise exception 'TEST ASSERTION FAILED: %',p_message; end if;
end;
$$;

create or replace function public.test_expect_error(p_sql text,p_expected text)
returns void language plpgsql
as $$
begin
  begin
    execute p_sql;
  exception when others then
    if position(p_expected in sqlerrm)>0 then return; end if;
    raise;
  end;
  raise exception 'TEST ASSERTION FAILED: expected error containing "%"',p_expected;
end;
$$;

insert into auth.users(id) values
 ('11111111-1111-4111-8111-111111111111'),
 ('22222222-2222-4222-8222-222222222222'),
 ('33333333-3333-4333-8333-333333333333'),
 ('44444444-4444-4444-8444-444444444444'),
 ('55555555-5555-4555-8555-555555555555'),
 ('66666666-6666-4666-8666-666666666666'),
 ('77777777-7777-4777-8777-777777777777'),
 ('88888888-8888-4888-8888-888888888888'),
 ('99999999-9999-4999-8999-999999999999'),
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa')
on conflict(id) do nothing;

insert into public.app_admins(user_id)
values('99999999-9999-4999-8999-999999999999')
on conflict(user_id) do nothing;
