-- Ensure every shared dating detail uses the same explicit community
-- boundary as Discover. Sexual orientation is not a proxy for community.
CREATE OR REPLACE FUNCTION public.get_shared_dating_details(p_user_ids uuid[])
RETURNS TABLE(user_id uuid, interests text[], smoking text, drinking text, activity_level text, pets text, children text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
begin
  if auth.uid() is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;
  if coalesce(cardinality(p_user_ids), 0) > 100 then
    raise exception 'A maximum of 100 member IDs can be requested' using errcode = '22023';
  end if;

  if private.member_dating_community(auth.uid()) is null then
    return;
  end if;

  return query
  with viewer_profile as (
    select viewer.id, viewer.gender_identity, viewer.interested_in
    from public.profiles viewer
    where viewer.id = auth.uid()
      and public.is_match_profile_complete(viewer.id)
      and (
        select pg_catalog.count(*)
        from public.profile_photos own_photo
        where own_photo.user_id = viewer.id
      ) >= 2
      and not exists (
        select 1
        from public.member_moderation own_moderation
        where own_moderation.user_id = viewer.id
          and (
            own_moderation.status = 'banned'
            or (
              own_moderation.status = 'suspended'
              and own_moderation.expires_at > pg_catalog.now()
            )
          )
      )
  ),
  visible_members as (
    select candidate.id
    from public.discover_profiles_secure(20050, 18, 99, null) visible
    join public.profiles candidate on candidate.id = visible.id
    cross join viewer_profile viewer
    where candidate.id = any(coalesce(p_user_ids, '{}'::uuid[]))
      and private.member_dating_community(candidate.id) =
          private.member_dating_community(viewer.id)
      and public.is_match_profile_complete(candidate.id)
      and (
        select pg_catalog.count(*)
        from public.profile_photos candidate_photo
        where candidate_photo.user_id = candidate.id
      ) >= 2
      and not exists (
        select 1
        from public.member_moderation candidate_moderation
        where candidate_moderation.user_id = candidate.id
          and (
            candidate_moderation.status = 'banned'
            or (
              candidate_moderation.status = 'suspended'
              and candidate_moderation.expires_at > pg_catalog.now()
            )
          )
      )
      and not exists (
        select 1
        from public.member_blocks block_record
        where (block_record.blocker_id = viewer.id and block_record.blocked_id = candidate.id)
           or (block_record.blocker_id = candidate.id and block_record.blocked_id = viewer.id)
      )
      and private.match_preference_accepts_gender(viewer.interested_in, candidate.gender_identity)
      and private.match_preference_accepts_gender(candidate.interested_in, viewer.gender_identity)
  )
  select
    d.user_id,
    case when d.share_interests then d.interests else null end,
    case when d.share_lifestyle then d.smoking else null end,
    case when d.share_lifestyle then d.drinking else null end,
    case when d.share_lifestyle then d.activity_level else null end,
    case when d.share_lifestyle then d.pets else null end,
    case when d.share_lifestyle then d.children else null end
  from public.member_dating_details d
  join visible_members visible on visible.id = d.user_id
  where d.user_id = any(coalesce(p_user_ids, '{}'::uuid[]))
    and (d.share_interests or d.share_lifestyle or d.share_profile_extras);
end;
$function$;

REVOKE ALL ON FUNCTION public.get_shared_dating_details(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_shared_dating_details(uuid[]) TO authenticated;
