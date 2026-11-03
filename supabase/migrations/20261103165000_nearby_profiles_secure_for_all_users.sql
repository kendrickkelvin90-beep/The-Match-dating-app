-- Allow every authenticated Nearby viewer to load privacy-safe profile cards.
-- Location coordinates remain private in private.profile_locations and are never returned.
CREATE OR REPLACE FUNCTION public.nearby_profiles_secure(
  p_max_distance_km double precision DEFAULT 50
)
RETURNS TABLE(
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
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  SELECT
    p.id,
    p.display_name,
    p.age,
    p.gender_identity,
    p.city,
    p.bio,
    p.nearby_current_city,
    p.nearby_current_state,
    p.is_verified,
    p.verification_level,
    public.calculate_distance_km(
      my_loc.nearby_latitude,
      my_loc.nearby_longitude,
      other_loc.nearby_latitude,
      other_loc.nearby_longitude
    ) AS distance_km
  FROM public.profiles p
  JOIN private.profile_locations other_loc
    ON other_loc.user_id = p.id
  JOIN private.profile_locations my_loc
    ON my_loc.user_id = auth.uid()
  WHERE auth.uid() IS NOT NULL
    AND p.id <> auth.uid()
    AND p.location_sharing IS TRUE
    AND other_loc.discovery_sharing IS TRUE
    AND EXISTS (
      SELECT 1
      FROM public.profiles viewer
      WHERE viewer.id = auth.uid()
        AND viewer.location_sharing IS TRUE
    )
    AND my_loc.nearby_latitude IS NOT NULL
    AND my_loc.nearby_longitude IS NOT NULL
    AND my_loc.nearby_updated_at >= now() - interval '7 days'
    AND other_loc.nearby_latitude IS NOT NULL
    AND other_loc.nearby_longitude IS NOT NULL
    AND other_loc.nearby_updated_at >= now() - interval '7 days'
    AND public.calculate_distance_km(
      my_loc.nearby_latitude,
      my_loc.nearby_longitude,
      other_loc.nearby_latitude,
      other_loc.nearby_longitude
    ) <= GREATEST(
      1,
      LEAST(COALESCE(p_max_distance_km, 50), 50)
    )
    AND public.can_interact_with_member(p.id) IS TRUE;
$function$;

REVOKE ALL ON FUNCTION public.nearby_profiles_secure(double precision) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nearby_profiles_secure(double precision) TO authenticated;
