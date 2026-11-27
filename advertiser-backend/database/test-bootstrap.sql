-- Minimal Supabase Auth compatibility layer for isolated local CI tests only.
-- Never deploy this file to Supabase or to the Match member project.
create role anon nologin;
create role authenticated nologin;
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
grant usage on schema auth to anon, authenticated, service_role;
grant execute on function auth.uid() to public;
grant execute on function auth.jwt() to public;
grant usage on schema public to anon, authenticated, service_role;
