-- Minimal Supabase Auth compatibility layer for isolated local CI tests only.
-- Never deploy this file to Supabase or to the Match member project.
create role anon nologin;
create role authenticated nologin;
create role authenticator nologin noinherit;
create role supabase_auth_admin nologin noinherit;
create role service_role nologin bypassrls;

create schema auth;
create table auth.users (
  id uuid primary key,
  email text,
  email_confirmed_at timestamptz,
  raw_user_meta_data jsonb not null default '{}'::jsonb
);
create or replace function auth.uid()
returns uuid
language sql
stable
as $function$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid;
$function$;
create or replace function auth.jwt()
returns jsonb
language sql
stable
as $function$
  select coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb;
$function$;
grant usage on schema auth to anon, authenticated, service_role, supabase_auth_admin;
grant execute on function auth.uid() to public;
grant execute on function auth.jwt() to public;
create table public.profiles (id uuid primary key);
alter table public.profiles enable row level security;
grant select (id) on public.profiles to supabase_auth_admin;
grant usage on schema public to anon, authenticated, service_role, authenticator, supabase_auth_admin;

grant select on public.profiles to anon, authenticated;
create policy member_profile_select on public.profiles
  for select to public using (auth.uid() is not null);

create schema storage;
create table storage.objects (id uuid primary key);
alter table storage.objects enable row level security;
grant usage on schema storage to anon, authenticated, service_role;
grant select on storage.objects to anon, authenticated;
create policy storage_test_read on storage.objects
  for select to public using (true);

create schema realtime;
create table realtime.messages (id uuid primary key);
alter table realtime.messages enable row level security;
grant usage on schema realtime to anon, authenticated, service_role;
grant select on realtime.messages to anon, authenticated;
create policy realtime_test_read on realtime.messages
  for select to public using (true);
