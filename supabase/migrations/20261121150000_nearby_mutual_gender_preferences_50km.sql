CREATE OR REPLACE FUNCTION private.preference_accepts_gender(p_preference text, p_gender text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT CASE
   WHEN lower(trim(coalesce(p_preference,''))) IN ('all genders','tous les genres','everyone','all') THEN true
   WHEN lower(trim(coalesce(p_preference,''))) IN ('men and women','men & women','both men and women','men, women') THEN lower(trim(coalesce(p_gender,''))) IN ('man','men','male','trans man','transmasculine','woman','women','female','trans woman','transfeminine')
   WHEN lower(trim(coalesce(p_preference,''))) IN ('men','male','man') THEN lower(trim(coalesce(p_gender,''))) IN ('man','men','male','trans man','transmasculine')
   WHEN lower(trim(coalesce(p_preference,''))) IN ('women','woman','female') THEN lower(trim(coalesce(p_gender,''))) IN ('woman','women','female','trans woman','transfeminine')
   ELSE false END;
$$;
CREATE OR REPLACE FUNCTION private.nearby_preferences_mutually_compatible(p_viewer_gender text,p_viewer_pref text,p_candidate_gender text,p_candidate_pref text)
RETURNS boolean LANGUAGE sql IMMUTABLE SET search_path='' AS $$
 SELECT private.preference_accepts_gender(p_viewer_pref,p_candidate_gender) AND private.preference_accepts_gender(p_candidate_pref,p_viewer_gender);
$$;
CREATE OR REPLACE FUNCTION public.nearby_map_markers_secure(p_max_distance_km double precision DEFAULT 50)
RETURNS TABLE(id uuid,map_latitude double precision,map_longitude double precision,nearby_current_city text,nearby_current_state text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT p.id,(floor(other_loc.nearby_latitude/0.025)*0.025+0.0125)::double precision,(floor(other_loc.nearby_longitude/0.025)*0.025+0.0125)::double precision,p.nearby_current_city,p.nearby_current_state
 FROM public.profiles p JOIN private.profile_locations other_loc ON other_loc.user_id=p.id JOIN private.profile_locations my_loc ON my_loc.user_id=auth.uid() JOIN public.profiles viewer ON viewer.id=auth.uid()
 WHERE auth.uid() IS NOT NULL AND p.id<>auth.uid() AND private.member_dating_community(auth.uid()) IS NOT NULL AND private.member_dating_community(p.id)=private.member_dating_community(auth.uid())
 AND private.nearby_preferences_mutually_compatible(viewer.gender_identity,viewer.interested_in,p.gender_identity,p.interested_in)
 AND p.location_sharing IS TRUE AND other_loc.discovery_sharing IS TRUE AND viewer.location_sharing IS TRUE
 AND my_loc.nearby_latitude IS NOT NULL AND my_loc.nearby_longitude IS NOT NULL AND my_loc.nearby_updated_at>=now()-interval '7 days'
 AND other_loc.nearby_latitude IS NOT NULL AND other_loc.nearby_longitude IS NOT NULL AND other_loc.nearby_updated_at>=now()-interval '7 days'
 AND public.calculate_distance_km(my_loc.nearby_latitude,my_loc.nearby_longitude,other_loc.nearby_latitude,other_loc.nearby_longitude)<=GREATEST(1,LEAST(COALESCE(p_max_distance_km,50),50)) AND public.can_interact_with_member(p.id) IS TRUE;
$$;
CREATE OR REPLACE FUNCTION public.premium_nearby_profiles_secure(p_max_distance_km double precision DEFAULT 50)
RETURNS TABLE(id uuid,display_name text,age smallint,gender_identity text,city text,bio text,nearby_current_city text,nearby_current_state text,is_verified boolean,verification_level text,distance_km double precision)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path='' AS $$
 SELECT p.id,p.display_name,p.age,p.gender_identity,p.city,p.bio,p.nearby_current_city,p.nearby_current_state,p.is_verified,p.verification_level,public.calculate_distance_km(my_loc.nearby_latitude,my_loc.nearby_longitude,other_loc.nearby_latitude,other_loc.nearby_longitude)
 FROM public.profiles p JOIN private.profile_locations other_loc ON other_loc.user_id=p.id JOIN private.profile_locations my_loc ON my_loc.user_id=auth.uid() JOIN public.profiles viewer ON viewer.id=auth.uid()
 WHERE auth.uid() IS NOT NULL AND (EXISTS(SELECT 1 FROM public.premium_memberships pm WHERE pm.user_id=auth.uid() AND pm.premium_until>now()) OR public.match_plus_active_tier() IN('plus','quarterly','annual'))
 AND p.id<>auth.uid() AND private.member_dating_community(auth.uid()) IS NOT NULL AND private.member_dating_community(p.id)=private.member_dating_community(auth.uid())
 AND private.nearby_preferences_mutually_compatible(viewer.gender_identity,viewer.interested_in,p.gender_identity,p.interested_in)
 AND p.location_sharing IS TRUE AND other_loc.discovery_sharing IS TRUE AND viewer.location_sharing IS TRUE
 AND my_loc.nearby_latitude IS NOT NULL AND my_loc.nearby_longitude IS NOT NULL AND my_loc.nearby_updated_at>=now()-interval '7 days'
 AND other_loc.nearby_latitude IS NOT NULL AND other_loc.nearby_longitude IS NOT NULL AND other_loc.nearby_updated_at>=now()-interval '7 days'
 AND public.calculate_distance_km(my_loc.nearby_latitude,my_loc.nearby_longitude,other_loc.nearby_latitude,other_loc.nearby_longitude)<=GREATEST(1,LEAST(COALESCE(p_max_distance_km,50),50)) AND public.can_interact_with_member(p.id) IS TRUE;
$$;