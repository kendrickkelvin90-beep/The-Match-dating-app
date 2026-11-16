-- Enforce mutual dating preferences without inferring compatibility from sexual orientation.
-- A member's stated gender and the other member's explicit "interested in" choice
-- must accept one another. Orientation is identity information, not a substitute
-- for an explicit dating preference.

begin;

create or replace function private.match_preference_accepts_gender(
  p_preference text,
  p_gender_identity text
)
returns boolean
language sql
immutable
set search_path = ''
as $function$
  select case
    when pg_catalog.lower(pg_catalog.btrim(coalesce(p_preference, '')))
      in ('all genders', 'everyone', 'not sure yet', 'i''ll decide later')
      then true
    when pg_catalog.lower(pg_catalog.btrim(coalesce(p_preference, '')))
      in ('men', 'man')
      then pg_catalog.lower(coalesce(p_gender_identity, '')) like '%man%'
       and pg_catalog.lower(coalesce(p_gender_identity, '')) not like '%woman%'
    when pg_catalog.lower(pg_catalog.btrim(coalesce(p_preference, '')))
      in ('women', 'woman')
      then pg_catalog.lower(coalesce(p_gender_identity, '')) like '%woman%'
    when pg_catalog.lower(pg_catalog.btrim(coalesce(p_preference, '')))
      in ('non-binary people', 'nonbinary people', 'non-binary', 'nonbinary')
      then pg_catalog.lower(coalesce(p_gender_identity, '')) like '%non-binary%'
        or pg_catalog.lower(coalesce(p_gender_identity, '')) like '%nonbinary%'
    else false
  end;
$function$;

revoke all on function private.match_preference_accepts_gender(text, text)
  from public, anon, authenticated;

-- Server-side eligibility gate for future interest-based matchmaking.
-- Returns candidate IDs only; it never exposes profile rows or interest data.
-- This is additive and does not change the existing Discover RPC or frontend.


create or replace function public.matchmaking_eligible_candidate_ids(
  p_max_distance_km double precision default 20050,
  p_min_age integer default 18,
  p_max_age integer default 79,
  p_city text default null,
  p_show_me text default 'everyone',
  p_role_preferences text[] default '{}'::text[],
  p_verified_only boolean default false,
  p_max_results integer default 100
)
returns table(user_id uuid)
language plpgsql
volatile
security definer
set search_path = ''
as $function$
declare
  v_viewer_id uuid := auth.uid();
  v_is_premium boolean := false;
  v_allowed_roles text[] := array[
    'Top', 'Bottom', 'Versatile', 'Vers Top', 'Vers Bottom', 'Side',
    'Dominant Top', 'Dominant Bottom', 'Submissive Top',
    'Submissive Bottom', 'Switch', 'Exploring'
  ];
begin
  if v_viewer_id is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  if coalesce(p_show_me, 'everyone') not in ('everyone', 'men', 'women', 'nonbinary') then
    raise exception 'Invalid gender discovery filter' using errcode = '22023';
  end if;

  if coalesce(cardinality(p_role_preferences), 0) > 12
     or exists (
       select 1
       from unnest(coalesce(p_role_preferences, '{}'::text[])) requested(role_name)
       where not (requested.role_name = any(v_allowed_roles))
     ) then
    raise exception 'Invalid role discovery filter' using errcode = '22023';
  end if;

  select exists (
    select 1
    from public.premium_memberships pm
    where pm.user_id = v_viewer_id
      and pm.premium_until > pg_catalog.now()
  ) into v_is_premium;

  if (coalesce(cardinality(p_role_preferences), 0) > 0 or coalesce(p_verified_only, false))
     and not v_is_premium then
    raise exception 'Advanced discovery filters require an active Premium membership'
      using errcode = '42501';
  end if;

  return query
  with viewer_is_eligible as (
    select 1
    from public.profiles viewer
    where viewer.id = v_viewer_id
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
  discover_candidates as (
    select
      discovered.id as candidate_id,
      discovered.gender_identity,
      discovered.is_verified,
      discovered.verification_level,
      discovered.sexual_roles
    from public.discover_profiles_secure(
      p_max_distance_km,
      p_min_age,
      p_max_age,
      p_city
    ) discovered
    join public.profiles candidate on candidate.id = discovered.id
    where exists (select 1 from viewer_is_eligible)
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
        where (block_record.blocker_id = v_viewer_id and block_record.blocked_id = candidate.id)
           or (block_record.blocker_id = candidate.id and block_record.blocked_id = v_viewer_id)
      )
      and exists (
        select 1
        from public.profiles viewer
        where viewer.id = v_viewer_id
          and private.match_preference_accepts_gender(viewer.interested_in, candidate.gender_identity)
          and private.match_preference_accepts_gender(candidate.interested_in, viewer.gender_identity)
      )
      -- A straight member is shown only other members who explicitly selected
      -- Straight / heterosexual. No orientation is inferred from gender.
      and (
        coalesce((
          select viewer_onboarding.answers ->> 'sexual_orientation'
          from public.member_onboarding viewer_onboarding
          where viewer_onboarding.user_id = v_viewer_id
        ), '') <> 'Straight / heterosexual'
        or exists (
          select 1
          from public.member_onboarding candidate_onboarding
          where candidate_onboarding.user_id = candidate.id
            and candidate_onboarding.answers ->> 'sexual_orientation' = 'Straight / heterosexual'
        )
      )
      and (
        coalesce(p_show_me, 'everyone') = 'everyone'
        or (
          p_show_me = 'men'
          and pg_catalog.lower(discovered.gender_identity) like '%man%'
          and pg_catalog.lower(discovered.gender_identity) not like '%woman%'
        )
        or (
          p_show_me = 'women'
          and pg_catalog.lower(discovered.gender_identity) like '%woman%'
        )
        or (
          p_show_me = 'nonbinary'
          and (
            pg_catalog.lower(discovered.gender_identity) like '%non-binary%'
            or pg_catalog.lower(discovered.gender_identity) like '%nonbinary%'
          )
        )
      )
      and (
        coalesce(cardinality(p_role_preferences), 0) = 0
        or discovered.sexual_roles[1] = any(p_role_preferences)
      )
      and (
        not coalesce(p_verified_only, false)
        or discovered.is_verified
        or discovered.verification_level in ('basic', 'enhanced')
      )
  )
  select candidate_id
  from discover_candidates
  order by candidate_id
  limit greatest(1, least(coalesce(p_max_results, 100), 100));
end;
$function$;

revoke all on function public.matchmaking_eligible_candidate_ids(
  double precision, integer, integer, text, text, text[], boolean, integer
) from public, anon;
grant execute on function public.matchmaking_eligible_candidate_ids(
  double precision, integer, integer, text, text, text[], boolean, integer
) to authenticated;

comment on function public.matchmaking_eligible_candidate_ids(
  double precision, integer, integer, text, text, text[], boolean, integer
) is
  'Returns only IDs from the existing Discover candidate pool after server-side profile-completeness, photo-count, moderation, reciprocal-block, mutual gender-preference compatibility, and supported preference checks. Does not expose member interests.';

commit;
