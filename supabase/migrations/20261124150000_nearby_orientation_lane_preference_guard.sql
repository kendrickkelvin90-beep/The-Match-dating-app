-- Nearby cards must enforce the dating lane and reciprocal preferences
-- directly. can_interact_with_member intentionally preserves old cross-lane
-- conversations, so it must never be the only Nearby eligibility boundary.

begin;

create or replace function public.nearby_profiles_secure(
  p_max_distance_km double precision default 50
)
returns table(
  id uuid,
  display_name text,
  age smallint,
  gender_identity text,
  city text,
  bio text,
  nearby_current_city text,
  nearby_current_state text,
  is_verified boolean,
  verification_level text,
  distance_km double precision
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    candidate.id,
    candidate.display_name,
    candidate.age,
    candidate.gender_identity,
    candidate.city,
    candidate.bio,
    candidate.nearby_current_city,
    candidate.nearby_current_state,
    candidate.is_verified,
    candidate.verification_level,
    public.calculate_distance_km(
      viewer_location.nearby_latitude,
      viewer_location.nearby_longitude,
      candidate_location.nearby_latitude,
      candidate_location.nearby_longitude
    ) as distance_km
  from public.profiles candidate
  join public.profiles viewer
    on viewer.id = auth.uid()
  join private.profile_locations viewer_location
    on viewer_location.user_id = viewer.id
  join private.profile_locations candidate_location
    on candidate_location.user_id = candidate.id
  where auth.uid() is not null
    and candidate.id <> viewer.id
    and viewer.location_sharing is true
    and candidate.location_sharing is true
    and viewer_location.nearby_latitude is not null
    and viewer_location.nearby_longitude is not null
    and viewer_location.nearby_updated_at >= pg_catalog.now() - interval '7 days'
    and candidate_location.nearby_latitude is not null
    and candidate_location.nearby_longitude is not null
    and candidate_location.nearby_updated_at >= pg_catalog.now() - interval '7 days'
    and candidate_location.discovery_sharing is true
    -- Explicit lane equality is essential: existing chats may remain valid
    -- across a later lane change, but must not leak a profile into Nearby.
    and private.member_dating_community(viewer.id) is not null
    and private.member_dating_community(candidate.id) =
        private.member_dating_community(viewer.id)
    and private.match_preference_accepts_gender(viewer.interested_in, candidate.gender_identity)
    and private.match_preference_accepts_gender(candidate.interested_in, viewer.gender_identity)
    and private.member_meets_partner_preferences(viewer.id, candidate.id)
    and private.member_meets_partner_preferences(candidate.id, viewer.id)
    and public.can_interact_with_member(candidate.id) is true
    and public.calculate_distance_km(
      viewer_location.nearby_latitude,
      viewer_location.nearby_longitude,
      candidate_location.nearby_latitude,
      candidate_location.nearby_longitude
    ) <= greatest(1, least(coalesce(p_max_distance_km, 50), 50));
$function$;

revoke all on function public.nearby_profiles_secure(double precision)
  from public, anon;
grant execute on function public.nearby_profiles_secure(double precision)
  to authenticated;

comment on function public.nearby_profiles_secure(double precision) is
  'Returns privacy-safe Nearby cards only for members in the same orientation-derived dating lane with reciprocal gender and partner-preference compatibility, fresh consented location sharing, and a maximum 50 km radius. Existing cross-lane conversations do not bypass Nearby separation.';

commit;
