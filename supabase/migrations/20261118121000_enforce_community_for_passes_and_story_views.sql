-- Close interaction paths that could bypass the community boundary.
CREATE OR REPLACE FUNCTION private.enforce_same_dating_community_on_pass()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
declare
  v_passer_community text;
  v_passed_community text;
begin
  v_passer_community := private.member_dating_community(new.passer_id);
  v_passed_community := private.member_dating_community(new.passed_id);
  if v_passer_community is null or v_passed_community is null then
    raise exception 'Both members must choose a dating community before recording a pass.'
      using errcode = '23514';
  end if;
  if v_passer_community <> v_passed_community then
    raise exception 'You can only interact with members in your own dating community.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

DROP TRIGGER IF EXISTS enforce_same_dating_community_on_pass ON public.profile_passes;
CREATE TRIGGER enforce_same_dating_community_on_pass
BEFORE INSERT OR UPDATE OF passer_id, passed_id ON public.profile_passes
FOR EACH ROW EXECUTE FUNCTION private.enforce_same_dating_community_on_pass();

REVOKE ALL ON FUNCTION private.enforce_same_dating_community_on_pass() FROM PUBLIC, anon, authenticated;

DROP POLICY IF EXISTS "Members can record their own story views" ON public.story_views;
CREATE POLICY "Members can record their own story views"
ON public.story_views
FOR INSERT
TO authenticated
WITH CHECK (
  auth.uid() = viewer_id
  AND EXISTS (
    SELECT 1
    FROM public.stories s
    WHERE s.id = story_views.story_id
      AND s.user_id <> auth.uid()
      AND s.expires_at > now()
      AND (
        (s.audience = 'everyone' AND private.can_view_story_from_owner(s.user_id))
        OR (
          s.audience = 'matches'
          AND public.can_interact_with_member(s.user_id)
          AND public.are_users_mutual_matches(auth.uid(), s.user_id)
        )
      )
  )
);
