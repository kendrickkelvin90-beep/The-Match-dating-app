-- Minimal isolated fixture for the View Once claim migration.
create extension if not exists pgcrypto;
do $roles$
begin
  if not exists(select 1 from pg_roles where rolname='authenticated') then
    create role authenticated nologin;
  end if;
end
$roles$;
create schema if not exists auth;
create or replace function auth.uid()
returns uuid language sql stable
as $$ select nullif(current_setting('request.jwt.claim.sub', true),'')::uuid $$;

create table public.chat_media (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null,
  receiver_id uuid not null,
  storage_path text not null,
  media_type text not null,
  view_once boolean not null default false,
  opened_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.test_premium_senders(user_id uuid primary key);
create table public.test_mutual_matches(user_a uuid not null,user_b uuid not null,primary key(user_a,user_b));

create or replace function public.can_interact_with_member(p_member_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select p_member_id is not null $$;

create or replace function public.is_match_premium(p_user_id uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.test_premium_senders where user_id=p_user_id) $$;

create or replace function public.are_users_mutual_matches(p_user_a uuid,p_user_b uuid)
returns boolean language sql stable security definer set search_path=''
as $$ select exists(select 1 from public.test_mutual_matches where (user_a=p_user_a and user_b=p_user_b) or (user_a=p_user_b and user_b=p_user_a)) $$;

grant usage on schema auth to authenticated;
grant execute on function auth.uid() to public;
grant execute on function public.can_interact_with_member(uuid) to authenticated;
grant execute on function public.is_match_premium(uuid) to authenticated;
grant execute on function public.are_users_mutual_matches(uuid,uuid) to authenticated;

insert into public.test_premium_senders values ('11111111-1111-4111-8111-111111111111');
insert into public.test_mutual_matches values ('55555555-5555-4555-8555-555555555555','66666666-6666-4666-8666-666666666666');

insert into public.chat_media(id,sender_id,receiver_id,storage_path,media_type,view_once)
values
 ('aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa','11111111-1111-4111-8111-111111111111','22222222-2222-4222-8222-222222222222','11111111-1111-4111-8111-111111111111/once.jpg','image',true),
 ('bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb','33333333-3333-4333-8333-333333333333','44444444-4444-4444-8444-444444444444','33333333-3333-4333-8333-333333333333/blocked.jpg','image',true),
 ('cccccccc-cccc-4ccc-8ccc-cccccccccccc','55555555-5555-4555-8555-555555555555','66666666-6666-4666-8666-666666666666','55555555-5555-4555-8555-555555555555/mutual.jpg','image',true);

create or replace function public.test_assert(p_condition boolean,p_message text)
returns void language plpgsql
as $$
begin
  if p_condition is distinct from true then
    raise exception 'TEST ASSERTION FAILED: %',p_message;
  end if;
end;
$$;
