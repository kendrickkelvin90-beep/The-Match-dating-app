-- Pin SECURITY DEFINER functions to an empty search_path.
-- All application relations and helper functions referenced by these routines
-- are schema-qualified; pg_catalog built-ins remain implicitly available.
-- This migration has already been applied to the connected production project.
ALTER FUNCTION public.can_interact_with_member(uuid) SET search_path = '';
ALTER FUNCTION public.claim_view_once_chat_media(uuid) SET search_path = '';
ALTER FUNCTION public.enforce_story_upload_limit() SET search_path = '';
ALTER FUNCTION public.hide_chat_message_for_me(uuid) SET search_path = '';
ALTER FUNCTION public.is_match_profile_complete(uuid) SET search_path = '';
ALTER FUNCTION public.mark_message_receipt(uuid, boolean) SET search_path = '';
ALTER FUNCTION public.notify_admins_verification_grace_expired() SET search_path = '';
ALTER FUNCTION public.notify_expired_premium() SET search_path = '';
ALTER FUNCTION public.notify_free_story_uploaded() SET search_path = '';
ALTER FUNCTION public.unsend_chat_message(uuid) SET search_path = '';
