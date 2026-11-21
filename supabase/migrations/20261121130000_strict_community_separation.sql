-- Strict same-community gates for secure discovery and location surfaces.
-- Applied to the live Supabase project as migration strict_community_separation_and_gps_column_privacy.
-- Note: coordinate-column SELECT revocation still requires a separate privilege review.
CREATE OR REPLACE FUNCTION public.can_interact_with_member(target_user_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT auth.uid() IS NOT NULL AND target_user_id IS NOT NULL AND target_user_id<>auth.uid()
 AND private.member_dating_community(auth.uid()) IS NOT NULL
 AND private.member_dating_community(target_user_id)=private.member_dating_community(auth.uid())
 AND NOT EXISTS(SELECT 1 FROM public.member_moderation m WHERE m.user_id IN(auth.uid(),target_user_id)
 AND (m.status='banned' OR (m.status='suspended' AND m.expires_at>now())))
 AND NOT EXISTS(SELECT 1 FROM public.member_blocks b WHERE (b.blocker_id=auth.uid() AND b.blocked_id=target_user_id)
 OR (b.blocker_id=target_user_id AND b.blocked_id=auth.uid()));
$function$;

CREATE OR REPLACE FUNCTION public.discover_profiles_secure(p_max_distance_km double precision DEFAULT 20050,p_min_age integer DEFAULT 18,p_max_age integer DEFAULT 79,p_city text DEFAULT NULL)
RETURNS TABLE(id uuid,display_name text,age smallint,gender_identity text,interested_in text,bio text,city text,is_verified boolean,sexual_roles text[],verification_level text,distance_km double precision)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT p.id,p.display_name,p.age,p.gender_identity,p.interested_in,p.bio,p.city,p.is_verified,p.sexual_roles,p.verification_level,
 CASE WHEN COALESCE(my_loc.discovery_sharing,false) AND my_loc.discovery_latitude IS NOT NULL AND my_loc.discovery_longitude IS NOT NULL
 AND COALESCE(other_loc.discovery_sharing,false) AND other_loc.discovery_latitude IS NOT NULL AND other_loc.discovery_longitude IS NOT NULL
 THEN public.calculate_distance_km(my_loc.discovery_latitude,my_loc.discovery_longitude,other_loc.discovery_latitude,other_loc.discovery_longitude) ELSE NULL END
 FROM public.profiles p LEFT JOIN private.profile_locations my_loc ON my_loc.user_id=auth.uid()
 LEFT JOIN private.profile_locations other_loc ON other_loc.user_id=p.id
 WHERE auth.uid() IS NOT NULL AND p.id<>auth.uid()
 AND private.member_dating_community(auth.uid()) IS NOT NULL
 AND private.member_dating_community(p.id)=private.member_dating_community(auth.uid())
 AND public.can_interact_with_member(p.id) IS TRUE AND p.age IS NOT NULL
 AND p.age BETWEEN GREATEST(18,COALESCE(p_min_age,18))
 AND LEAST(CASE WHEN EXISTS(SELECT 1 FROM public.premium_memberships pm WHERE pm.user_id=auth.uid() AND pm.premium_until>now()) THEN 99 ELSE 79 END,
 GREATEST(COALESCE(p_min_age,18),COALESCE(p_max_age,79)))
 AND (NULLIF(BTRIM(COALESCE(p_city,'')),'') IS NULL OR regexp_replace(lower(COALESCE(p.city,'')),'[^a-z0-9]+',' ','g')
 LIKE '%'||regexp_replace(lower(BTRIM(p_city)),'[^a-z0-9]+',' ','g')||'%')
 AND (NOT COALESCE(my_loc.discovery_sharing,false) OR my_loc.discovery_latitude IS NULL OR my_loc.discovery_longitude IS NULL
 OR NOT COALESCE(other_loc.discovery_sharing,false) OR other_loc.discovery_latitude IS NULL OR other_loc.discovery_longitude IS NULL
 OR public.calculate_distance_km(my_loc.discovery_latitude,my_loc.discovery_longitude,other_loc.discovery_latitude,other_loc.discovery_longitude)
 <=GREATEST(1,LEAST(COALESCE(p_max_distance_km,20050),20050)));
$function$;

CREATE OR REPLACE FUNCTION public.nearby_map_markers_secure(p_max_distance_km double precision DEFAULT 50)
RETURNS TABLE(id uuid,map_latitude double precision,map_longitude double precision,nearby_current_city text,nearby_current_state text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT p.id,(floor(other_loc.nearby_latitude/0.025)*0.025+0.0125)::double precision,
 (floor(other_loc.nearby_longitude/0.025)*0.025+0.0125)::double precision,p.nearby_current_city,p.nearby_current_state
 FROM public.profiles p JOIN private.profile_locations other_loc ON other_loc.user_id=p.id
 JOIN private.profile_locations my_loc ON my_loc.user_id=auth.uid()
 WHERE auth.uid() IS NOT NULL AND p.id<>auth.uid()
 AND private.member_dating_community(auth.uid()) IS NOT NULL
 AND private.member_dating_community(p.id)=private.member_dating_community(auth.uid())
 AND p.location_sharing IS TRUE AND other_loc.discovery_sharing IS TRUE
 AND EXISTS(SELECT 1 FROM public.profiles viewer WHERE viewer.id=auth.uid() AND viewer.location_sharing IS TRUE)
 AND my_loc.nearby_latitude IS NOT NULL AND my_loc.nearby_longitude IS NOT NULL AND my_loc.nearby_updated_at>=now()-interval '7 days'
 AND other_loc.nearby_latitude IS NOT NULL AND other_loc.nearby_longitude IS NOT NULL AND other_loc.nearby_updated_at>=now()-interval '7 days'
 AND public.calculate_distance_km(my_loc.nearby_latitude,my_loc.nearby_longitude,other_loc.nearby_latitude,other_loc.nearby_longitude)
 <=GREATEST(1,LEAST(COALESCE(p_max_distance_km,50),50)) AND public.can_interact_with_member(p.id) IS TRUE;
$function$;

CREATE OR REPLACE FUNCTION public.premium_nearby_profiles_secure(p_max_distance_km double precision DEFAULT 100)
RETURNS TABLE(id uuid,display_name text,age smallint,gender_identity text,city text,bio text,nearby_current_city text,nearby_current_state text,is_verified boolean,verification_level text,distance_km double precision)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''
AS $function$
 SELECT p.id,p.display_name,p.age,p.gender_identity,p.city,p.bio,p.nearby_current_city,p.nearby_current_state,p.is_verified,p.verification_level,
 public.calculate_distance_km(my_loc.nearby_latitude,my_loc.nearby_longitude,other_loc.nearby_latitude,other_loc.nearby_longitude)
 FROM public.profiles p JOIN private.profile_locations other_loc ON other_loc.user_id=p.id JOIN private.profile_locations my_loc ON my_loc.user_id=auth.uid()
 WHERE auth.uid() IS NOT NULL AND (EXISTS(SELECT 1 FROM public.premium_memberships pm WHERE pm.user_id=auth.uid() AND pm.premium_until>now()) OR public.match_plus_active_tier() IN('plus','quarterly','annual'))
 AND p.id<>auth.uid() AND private.member_dating_community(auth.uid()) IS NOT NULL
 AND private.member_dating_community(p.id)=private.member_dating_community(auth.uid())
 AND p.location_sharing IS TRUE AND other_loc.discovery_sharing IS TRUE
 AND EXISTS(SELECT 1 FROM public.profiles viewer WHERE viewer.id=auth.uid() AND viewer.location_sharing IS TRUE)
 AND my_loc.nearby_latitude IS NOT NULL AND my_loc.nearby_longitude IS NOT NULL AND my_loc.nearby_updated_at>=now()-interval '7 days'
 AND other_loc.nearby_latitude IS NOT NULL AND other_loc.nearby_longitude IS NOT NULL AND other_loc.nearby_updated_at>=now()-interval '7 days'
 AND public.calculate_distance_km(my_loc.nearby_latitude,my_loc.nearby_longitude,other_loc.nearby_latitude,other_loc.nearby_longitude)
 <=GREATEST(1,LEAST(COALESCE(p_max_distance_km,100),100)) AND public.can_interact_with_member(p.id) IS TRUE;
$function$;
