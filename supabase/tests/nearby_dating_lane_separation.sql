\set ON_ERROR_STOP on

-- This test runs after the orientation-derived lane test, which creates an
-- existing conversation between LGBTQ+ member 1 and straight member 2.
-- That historical connection must not bypass Nearby lane separation.

update public.profiles
set location_sharing = true
where id in (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000010'
);

update public.profiles
set gender_identity = 'Man',
    interested_in = 'Men',
    nearby_current_city = 'Test City',
    nearby_current_state = 'Test State'
where id in (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000010'
);

update private.profile_locations
set nearby_latitude = 6.5244,
    nearby_longitude = 3.3792,
    nearby_updated_at = now(),
    discovery_sharing = true
where user_id = '00000000-0000-4000-8000-000000000001';

update private.profile_locations
set nearby_latitude = 6.5250,
    nearby_longitude = 3.3800,
    nearby_updated_at = now(),
    discovery_sharing = true
where user_id = '00000000-0000-4000-8000-000000000010';

update private.profile_locations
set nearby_latitude = 6.5260,
    nearby_longitude = 3.3810,
    nearby_updated_at = now(),
    discovery_sharing = true
where user_id = '00000000-0000-4000-8000-000000000002';

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);

do $nearby_lane$
declare
  found_ids uuid[];
begin
  if not public.can_interact_with_member('00000000-0000-4000-8000-000000000002') then
    raise exception 'Fixture must preserve the historical cross-lane conversation';
  end if;

  select array_agg(id order by id)
    into found_ids
  from public.nearby_profiles_secure();

  if found_ids is distinct from array['00000000-0000-4000-8000-000000000010'::uuid] then
    raise exception 'Nearby must include only compatible same-lane members and exclude historical cross-lane chats; got %', found_ids;
  end if;
end;
$nearby_lane$;

-- A one-sided gender preference must exclude an otherwise nearby same-lane
-- member from the cards returned by the secure Nearby RPC.
update public.profiles
set interested_in = 'Women'
where id = '00000000-0000-4000-8000-000000000010';

do $nearby_reciprocal_gender$
begin
  if exists (
    select 1 from public.nearby_profiles_secure()
    where id = '00000000-0000-4000-8000-000000000010'
  ) then
    raise exception 'Nearby must enforce reciprocal gender preferences';
  end if;
end;
$nearby_reciprocal_gender$;

-- Restore reciprocal compatibility, then prove the 50 km ceiling cannot be
-- widened by passing a larger RPC argument.
update public.profiles
set interested_in = 'Men'
where id = '00000000-0000-4000-8000-000000000010';

update private.profile_locations
set nearby_longitude = 4.1000
where user_id = '00000000-0000-4000-8000-000000000010';

do $nearby_radius$
begin
  if exists (
    select 1 from public.nearby_profiles_secure(200)
    where id = '00000000-0000-4000-8000-000000000010'
  ) then
    raise exception 'Nearby must remain capped at 50 km even when a larger distance is requested';
  end if;
end;
$nearby_radius$;

select 'Nearby dating-lane, reciprocal-preference, and 50 km tests passed' as result;
