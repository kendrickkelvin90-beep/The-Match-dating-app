-- Restrict functions intended for signed-in members.
-- This migration was already applied to the connected Supabase project.
-- Keep authenticated access intact; trigger execution is unaffected by caller grants.
REVOKE EXECUTE ON FUNCTION public.are_users_mutual_matches(uuid, uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.check_mutual_like(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.enforce_story_upload_limit() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.get_my_incoming_like_count() FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_match_premium(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.is_match_profile_complete(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.notify_admins_verification_grace_expired() FROM PUBLIC, anon;
