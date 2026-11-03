-- Enforce Discovery distance and age entitlements in the database, not only the UI.
create or replace function public.discover_profiles_secure(
  p_max_distance_km double precision default 50,
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
      when coalesce(my_loc.discovery_sharing,false)
       and my_loc.discovery_latitude is not null
       and my_loc.discovery_longitude is not null
       and coalesce(other_loc.discovery_sharing,false)
       and other_loc.discovery_latitude is not null
       and other_loc.discovery_longitude is not null
      then public.calculate_distance_km(
        my_loc.discovery_latitude,my_loc.discovery_longitude,
        other_loc.discovery_latitude,other_loc.discovery_longitude
      )
      else null
    end as distance_km
  from public.profiles p
  left join private.profile_locations my_loc on my_loc.user_id=auth.uid()
  left join private.profile_locations other_loc on other_loc.user_id=p.id
  where auth.uid() is not null
    and p.id<>auth.uid()
    and p.age is not null
    and p.age between greatest(18,coalesce(p_min_age,18))
      and least(
        case when exists(
          select 1 from public.premium_memberships pm
          where pm.user_id=auth.uid() and pm.premium_until>now()
        ) then 99 else 79 end,
        greatest(coalesce(p_min_age,18),coalesce(p_max_age,79))
      )
    and (
      nullif(btrim(coalesce(p_city,'')),'') is null
      or coalesce(p.city,'') ilike '%'||btrim(p_city)||'%'
    )
    and (
      not coalesce(my_loc.discovery_sharing,false)
      or my_loc.discovery_latitude is null
      or my_loc.discovery_longitude is null
      or not coalesce(other_loc.discovery_sharing,false)
      or other_loc.discovery_latitude is null
      or other_loc.discovery_longitude is null
      or public.calculate_distance_km(
        my_loc.discovery_latitude,my_loc.discovery_longitude,
        other_loc.discovery_latitude,other_loc.discovery_longitude
      ) <= greatest(
        1,
        least(
          coalesce(p_max_distance_km,50),
          case when exists(
            select 1 from public.premium_memberships pm
            where pm.user_id=auth.uid() and pm.premium_until>now()
          ) then 200 else 50 end
        )
      )
    );
$$;

revoke all on function public.discover_profiles_secure(double precision,integer,integer,text) from public,anon;
grant execute on function public.discover_profiles_secure(double precision,integer,integer,text) to authenticated;
