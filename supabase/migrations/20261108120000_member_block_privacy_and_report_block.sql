-- Member block privacy and mandatory report-and-block workflow.
-- Block rows remain available to administrators only; member-facing clients
-- cannot query identities from the member_blocks table.
ALTER TABLE public.member_blocks ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.member_blocks TO authenticated;
DROP POLICY IF EXISTS "Admins only can read member blocks" ON public.member_blocks;
CREATE POLICY "Admins can read member blocks"
ON public.member_blocks FOR SELECT TO authenticated
USING ((SELECT public.is_match_admin()));
CREATE POLICY "Admins only can read member blocks"
ON public.member_blocks AS RESTRICTIVE FOR SELECT TO authenticated
USING ((SELECT public.is_match_admin()));

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
    AND NOT EXISTS (
      SELECT 1
      FROM public.member_blocks mb
      WHERE (mb.blocker_id = auth.uid() AND mb.blocked_id = p.id)
         OR (mb.blocker_id = p.id AND mb.blocked_id = auth.uid())
    )
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

CREATE OR REPLACE FUNCTION public.submit_member_report_and_block(
  p_reported_user_id uuid,
  p_reason text,
  p_details text DEFAULT NULL,
  p_block_reason text DEFAULT 'Reported'
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_reporter uuid := auth.uid();
BEGIN
  IF v_reporter IS NULL THEN
    RAISE EXCEPTION 'You must be signed in to report a member';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.member_moderation mm
    WHERE mm.user_id = v_reporter
      AND (mm.status = 'banned' OR (mm.status = 'suspended' AND mm.expires_at > now()))
  ) THEN
    RAISE EXCEPTION 'Your account cannot submit reports right now';
  END IF;
  IF p_reported_user_id IS NULL OR p_reported_user_id = v_reporter THEN
    RAISE EXCEPTION 'Invalid member selected';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = p_reported_user_id)
     OR EXISTS (
       SELECT 1 FROM public.member_moderation mm
       WHERE mm.user_id = p_reported_user_id
         AND (mm.status = 'banned' OR (mm.status = 'suspended' AND mm.expires_at > now()))
     ) THEN
    RAISE EXCEPTION 'This member cannot be reported right now';
  END IF;
  IF length(btrim(coalesce(p_reason, ''))) < 3 OR length(p_reason) > 1000 THEN
    RAISE EXCEPTION 'A report reason between 3 and 1000 characters is required';
  END IF;

  INSERT INTO public.member_reports (
    reporter_id, reported_user_id, reason, details
  ) VALUES (
    v_reporter, p_reported_user_id, btrim(p_reason), nullif(btrim(coalesce(p_details, '')), '')
  );

  INSERT INTO public.member_blocks (blocker_id, blocked_id, block_reason)
  SELECT v_reporter, p_reported_user_id, coalesce(nullif(btrim(p_block_reason), ''), 'Reported')
  WHERE NOT EXISTS (
    SELECT 1 FROM public.member_blocks mb
    WHERE mb.blocker_id = v_reporter AND mb.blocked_id = p_reported_user_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_member_report_and_block(uuid,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_member_report_and_block(uuid,text,text,text) TO authenticated;
