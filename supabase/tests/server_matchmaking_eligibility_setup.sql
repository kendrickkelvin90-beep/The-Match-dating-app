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
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null,
  storage_path text not null unique,
  position integer not null default 0 check (position between 0 and 4),
  created_at timestamptz not null default now()
);
create table public.member_moderation (
  user_id uuid primary key,
  status text not null check (status in ('suspended', 'banned', 'restored')),
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  expires_at timestamptz,
  updated_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (
    (status = 'suspended' and expires_at is not null)
    or (status in ('banned', 'restored') and expires_at is null)
  )
);
create table public.member_blocks (
  blocker_id uuid not null,
  blocked_id uuid not null
);

-- Minimal Supabase Realtime authorization surface for the disposable CI DB.
create schema realtime;
create table realtime.messages (
  topic text not null,
  extension text not null,
  payload jsonb not null
);
create function realtime.topic()
returns text
language sql
stable
as $
  select nullif(current_setting('request.realtime.topic', true), '')
$;
alter table realtime.messages enable row level security;
grant usage on schema realtime to authenticated;
grant select, insert on realtime.messages to authenticated;
create table public.premium_memberships (
  user_id uuid primary key,
  premium_until timestamptz not null
);

create table public.member_onboarding (
  user_id uuid primary key,
  answers jsonb not null default '{}'::jsonb
);

create function public.is_match_profile_complete(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = target_user_id
      and p.age between 18 and 120
      and nullif(btrim(coalesce(p.display_name, '')), '') is not null
      and lower(btrim(coalesce(p.display_name, ''))) not in ('not listed', 'unknown', 'member')
      and nullif(btrim(coalesce(p.gender_identity, '')), '') is not null
      and lower(btrim(coalesce(p.gender_identity, ''))) <> 'not listed'
      and nullif(btrim(coalesce(p.interested_in, '')), '') is not null
      and lower(btrim(coalesce(p.interested_in, ''))) <> 'not listed'
      and nullif(btrim(coalesce(p.city, '')), '') is not null
      and lower(btrim(coalesce(p.city, ''))) <> 'not listed'
      and nullif(btrim(coalesce(p.bio, '')), '') is not null
      and lower(btrim(coalesce(p.bio, ''))) not in ('not listed', 'no description added yet.')
      and coalesce(array_length(p.sexual_roles, 1), 0) > 0
      and exists (
        select 1 from public.profile_photos ph
        where ph.user_id = p.id and ph.position = 0
      )
  );
$$;


-- Mirror the production location table and distance helper so the eligibility
-- RPC is exercised against the same Discover contract as the live database.
create schema private;
create table private.profile_locations (
  user_id uuid primary key,
  discovery_latitude double precision,
  discovery_longitude double precision,
  discovery_updated_at timestamptz,
  discovery_sharing boolean not null default false,
  nearby_latitude double precision,
  nearby_longitude double precision,
  nearby_updated_at timestamptz,
  updated_at timestamptz not null default now()
);

create function public.calculate_distance_km(
  lat1 double precision, lon1 double precision,
  lat2 double precision, lon2 double precision
)
returns double precision
language sql
immutable
parallel safe
strict
set search_path = ''
as $$
  select 6371.0 * 2.0 * asin(
    sqrt(
      least(
        1.0,
        greatest(
          0.0,
          sin(radians(lat2 - lat1) / 2.0)^2
          + cos(radians(lat1)) * cos(radians(lat2))
          * sin(radians(lon2 - lon1) / 2.0)^2
        )
      )
    )
  );
$$;

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
  select
    p.id,
    p.display_name,
    p.age,
    p.gender_identity,
    p.interested_in,
    p.bio,
    p.city,
    p.is_verified,
    p.sexual_roles,
    p.verification_level,
    case
      when coalesce(my_loc.discovery_sharing, false)
        and my_loc.discovery_latitude is not null
        and my_loc.discovery_longitude is not null
        and coalesce(other_loc.discovery_sharing, false)
        and other_loc.discovery_latitude is not null
        and other_loc.discovery_longitude is not null
      then public.calculate_distance_km(
        my_loc.discovery_latitude,
        my_loc.discovery_longitude,
        other_loc.discovery_latitude,
        other_loc.discovery_longitude
      )
      else null
    end as distance_km
  from public.profiles p
  left join private.profile_locations my_loc on my_loc.user_id = auth.uid()
  left join private.profile_locations other_loc on other_loc.user_id = p.id
  where auth.uid() is not null
    and p.id <> auth.uid()
    and not exists (
      select 1
      from public.member_blocks mb
      where (mb.blocker_id = auth.uid() and mb.blocked_id = p.id)
         or (mb.blocker_id = p.id and mb.blocked_id = auth.uid())
    )
    and p.age is not null
    and p.age between greatest(18, coalesce(p_min_age, 18))
      and least(
        case
          when exists (
            select 1 from public.premium_memberships pm
            where pm.user_id = auth.uid() and pm.premium_until > now()
          ) then 99 else 79
        end,
        greatest(coalesce(p_min_age, 18), coalesce(p_max_age, 79))
      )
    and (
      nullif(btrim(coalesce(p_city, '')), '') is null
      or regexp_replace(lower(coalesce(p.city, '')), '[^a-z0-9]+', ' ', 'g')
         like '%' || regexp_replace(lower(btrim(p_city)), '[^a-z0-9]+', ' ', 'g') || '%'
    )
    and (
      not coalesce(my_loc.discovery_sharing, false)
      or my_loc.discovery_latitude is null
      or my_loc.discovery_longitude is null
      or not coalesce(other_loc.discovery_sharing, false)
      or other_loc.discovery_latitude is null
      or other_loc.discovery_longitude is null
      or public.calculate_distance_km(
        my_loc.discovery_latitude,
        my_loc.discovery_longitude,
        other_loc.discovery_latitude,
        other_loc.discovery_longitude
      ) <= greatest(1, least(coalesce(p_max_distance_km, 20050), 20050))
    );
$$;

insert into private.profile_locations
  (user_id, discovery_latitude, discovery_longitude, discovery_sharing)
values
  ('00000000-0000-4000-8000-000000000001', 6.5244, 3.3792, true),
  ('00000000-0000-4000-8000-000000000002', 6.5250, 3.3800, true),
  ('00000000-0000-4000-8000-000000000007', 9.0765, 7.3986, true),
  ('00000000-0000-4000-8000-000000000010', 9.0765, 7.3986, true);
