-- Server-side eligibility gate for future interest-based matchmaking.
-- Returns candidate IDs only; it never exposes profile rows or interest data.
-- This is additive and does not change the existing Discover RPC or frontend.

begin;

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
stable
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
      and viewer.age between 18 and 120
      and nullif(pg_catalog.btrim(viewer.display_name), '') is not null
      and nullif(pg_catalog.btrim(viewer.gender_identity), '') is not null
      and nullif(pg_catalog.btrim(viewer.interested_in), '') is not null
      and nullif(pg_catalog.btrim(viewer.city), '') is not null
      and nullif(pg_catalog.btrim(viewer.bio), '') is not null
      and coalesce(pg_catalog.cardinality(viewer.sexual_roles), 0) > 0
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
      and candidate.age between 18 and 120
      and nullif(pg_catalog.btrim(candidate.display_name), '') is not null
      and nullif(pg_catalog.btrim(candidate.gender_identity), '') is not null
      and nullif(pg_catalog.btrim(candidate.interested_in), '') is not null
      and nullif(pg_catalog.btrim(candidate.city), '') is not null
      and nullif(pg_catalog.btrim(candidate.bio), '') is not null
      and coalesce(pg_catalog.cardinality(candidate.sexual_roles), 0) > 0
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
  'Returns only IDs from the existing Discover candidate pool after server-side profile-completeness, photo-count, moderation, reciprocal-block, and supported preference checks. Does not expose member interests.';

commit;
