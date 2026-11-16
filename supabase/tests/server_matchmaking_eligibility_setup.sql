\set ON_ERROR_STOP on

create role anon nologin;
create role authenticated nologin;
create schema auth;
create function auth.uid()
returns uuid
language sql
stable
as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create table public.profiles (
  id uuid primary key,
  display_name text not null default '',
  gender_identity text not null default '',
  interested_in text not null default '',
  bio text not null default '',
  city text not null default '',
  age smallint,
  is_verified boolean not null default false,
  sexual_roles text[] not null default '{}',
  verification_level text not null default 'none'
);
create table public.profile_photos (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  storage_path text not null
);
create table public.member_moderation (
  user_id uuid primary key,
  status text not null,
  expires_at timestamptz
);
create table public.member_blocks (
  blocker_id uuid not null,
  blocked_id uuid not null
);
create table public.premium_memberships (
  user_id uuid primary key,
  premium_until timestamptz not null
);

create function public.discover_profiles_secure(
  p_max_distance_km double precision default 20050,
  p_min_age integer default 18,
  p_max_age integer default 79,
  p_city text default null
)
returns table(
  id uuid,
  display_name text,
  age smallint,
  gender_identity text,
  interested_in text,
  bio text,
  city text,
  is_verified boolean,
  sexual_roles text[],
  verification_level text,
  distance_km double precision
)
language sql
stable
security definer
set search_path = ''
as $$
  select p.id, p.display_name, p.age, p.gender_identity, p.interested_in,
         p.bio, p.city, p.is_verified, p.sexual_roles, p.verification_level,
         null::double precision
  from public.profiles p
  where p.id <> auth.uid()
    and p.age between greatest(18, coalesce(p_min_age, 18))
      and least(
        case when exists (
          select 1 from public.premium_memberships pm
          where pm.user_id = auth.uid() and pm.premium_until > now()
        ) then 99 else 79 end,
        greatest(coalesce(p_min_age, 18), coalesce(p_max_age, 79))
      )
    and (
      nullif(btrim(coalesce(p_city, '')), '') is null
      or lower(p.city) like '%' || lower(btrim(p_city)) || '%'
    )
$$;
