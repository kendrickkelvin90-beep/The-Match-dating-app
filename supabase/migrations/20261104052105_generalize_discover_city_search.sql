CREATE OR REPLACE FUNCTION public.discover_profiles_secure(
  p_max_distance_km double precision DEFAULT 20050,
  p_min_age integer DEFAULT 18,
  p_max_age integer DEFAULT 79,
  p_city text DEFAULT NULL::text
)
RETURNS TABLE(
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
    p.interested_in,
    p.bio,
    p.city,
    p.is_verified,
    p.sexual_roles,
    p.verification_level,
    CASE
      WHEN COALESCE(my_loc.discovery_sharing, false)
        AND my_loc.discovery_latitude IS NOT NULL
        AND my_loc.discovery_longitude IS NOT NULL
        AND COALESCE(other_loc.discovery_sharing, false)
        AND other_loc.discovery_latitude IS NOT NULL
        AND other_loc.discovery_longitude IS NOT NULL
      THEN public.calculate_distance_km(
        my_loc.discovery_latitude,
        my_loc.discovery_longitude,
        other_loc.discovery_latitude,
        other_loc.discovery_longitude
      )
      ELSE NULL
    END AS distance_km
  FROM public.profiles p
  LEFT JOIN private.profile_locations my_loc ON my_loc.user_id = auth.uid()
  LEFT JOIN private.profile_locations other_loc ON other_loc.user_id = p.id
  WHERE auth.uid() IS NOT NULL
    AND p.id <> auth.uid()
    AND p.age IS NOT NULL
    AND p.age BETWEEN GREATEST(18, COALESCE(p_min_age, 18))
      AND LEAST(
        CASE
          WHEN EXISTS (
            SELECT 1 FROM public.premium_memberships pm
            WHERE pm.user_id = auth.uid() AND pm.premium_until > now()
          ) THEN 99 ELSE 79
        END,
        GREATEST(COALESCE(p_min_age, 18), COALESCE(p_max_age, 79))
      )
    AND (
      NULLIF(BTRIM(COALESCE(p_city, '')), '') IS NULL
      OR regexp_replace(lower(COALESCE(p.city, '')), '[^a-z0-9]+', ' ', 'g')
         LIKE '%' || regexp_replace(lower(BTRIM(p_city)), '[^a-z0-9]+', ' ', 'g') || '%'
    )
    AND (
      NOT COALESCE(my_loc.discovery_sharing, false)
      OR my_loc.discovery_latitude IS NULL
      OR my_loc.discovery_longitude IS NULL
      OR NOT COALESCE(other_loc.discovery_sharing, false)
      OR other_loc.discovery_latitude IS NULL
      OR other_loc.discovery_longitude IS NULL
      OR public.calculate_distance_km(
        my_loc.discovery_latitude,
        my_loc.discovery_longitude,
        other_loc.discovery_latitude,
        other_loc.discovery_longitude
      ) <= GREATEST(1, LEAST(COALESCE(p_max_distance_km, 20050), 20050))
    );
$function$;