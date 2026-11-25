-- Unassigned profiles are visible in both Discover lanes, but remain read-only.
begin;
create or replace function public.discover_profiles_secure(
  p_max_distance_km double precision default 20050,
  p_min_age integer default 18,
  p_max_age integer default 79,
  p_city text default null
)
returns table(
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
language sql
stable
security definer
set search_path = ''
as $function$
  select
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
    case
      when coalesce(my_loc.discovery_sharing, false)
        and my_loc.discovery_latitude is not null
        and my_loc.discovery_longitude is not null
        and coalesce(other_loc.discovery_sharing, false)
        and other_loc.discovery_latitude is not null
        and other_loc.discovery_longitude is not null
      then public.calculate_distance_km(
        my_loc.discovery_latitude,
        my_loc.discovery_longitude,
        other_loc.discovery_latitude,
        other_loc.discovery_longitude
      )
      else null
    end as distance_km
  from public.profiles p
  left join private.profile_locations my_loc on my_loc.user_id = auth.uid()
  left join private.profile_locations other_loc on other_loc.user_id = p.id
  where auth.uid() is not null
    and p.id <> auth.uid()
    and public.is_match_profile_complete(auth.uid())
    and public.is_match_profile_complete(p.id)
    and (
      select pg_catalog.count(*)
      from public.profile_photos viewer_photo
      where viewer_photo.user_id = auth.uid()
    ) >= 2
    and (
      select pg_catalog.count(*)
      from public.profile_photos candidate_photo
      where candidate_photo.user_id = p.id
    ) >= 2
    and coalesce(p.profile_paused, false) is false
    and coalesce(p.discover_visibility, 'everyone') = 'everyone'
    and private.member_dating_community(auth.uid()) is not null
    and (private.member_dating_community(p.id) =
        private.member_dating_community(auth.uid())
      or private.member_dating_community(p.id) is null)
    and (private.member_dating_community(p.id) is null
      or public.can_interact_with_member(p.id) is true)
    and exists (
      select 1
      from public.profiles viewer
      where viewer.id = auth.uid()
        and private.match_preference_accepts_gender(viewer.interested_in, p.gender_identity)
        and private.match_preference_accepts_gender(p.interested_in, viewer.gender_identity)
        and private.member_meets_partner_preferences(viewer.id, p.id)
        and private.member_meets_partner_preferences(p.id, viewer.id)
    )
    and p.age is not null
    and p.age between greatest(18, coalesce(p_min_age, 18))
      and least(
        case
          when exists (
            select 1
            from public.premium_memberships membership
            where membership.user_id = auth.uid()
              and membership.premium_until > pg_catalog.now()
          ) then 99 else 79
        end,
        greatest(coalesce(p_min_age, 18), coalesce(p_max_age, 79))
      )
    and (
      nullif(btrim(coalesce(p_city, '')), '') is null
      or regexp_replace(lower(coalesce(p.city, '')), '[^a-z0-9]+', ' ', 'g')
         like '%' || regexp_replace(lower(btrim(p_city)), '[^a-z0-9]+', ' ', 'g') || '%'
    )
    and (
      not coalesce(my_loc.discovery_sharing, false)
      or my_loc.discovery_latitude is null
      or my_loc.discovery_longitude is null
      or not coalesce(other_loc.discovery_sharing, false)
      or other_loc.discovery_latitude is null
      or other_loc.discovery_longitude is null
      or public.calculate_distance_km(
        my_loc.discovery_latitude,
        my_loc.discovery_longitude,
        other_loc.discovery_latitude,
        other_loc.discovery_longitude
      ) <= greatest(1, least(coalesce(p_max_distance_km, 20050), 20050))
    );
$function$;
create or replace function public.matchmaking_eligible_candidate_ids(
  p_max_distance_km double precision default 20050,
  p_min_age integer default 18,
  p_max_age integer default 79,
  p_city text default null,
  p_show_me text default 'everyone',
  p_role_preferences text[] default '{}'::text[],
  p_verified_only boolean default false,
  p_connection_goal text default null,
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

  if p_connection_goal is not null
     and p_connection_goal not in ('relationship', 'dating', 'friendship', 'casual', 'exploring') then
    raise exception 'Invalid connection goal filter' using errcode = '22023';
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
      and private.member_meets_partner_preferences(v_viewer_id, candidate.id)
      and private.member_meets_partner_preferences(candidate.id, v_viewer_id)
      )
      -- Members are shown only others in the same private lane derived from
      -- their saved orientation; the orientation answer itself is never exposed.
      and (
        p_connection_goal is null
        or exists (
          select 1
          from public.member_onboarding goal_onboarding
          where goal_onboarding.user_id = candidate.id
            and case pg_catalog.lower(coalesce(goal_onboarding.answers ->> 'relationship_goal', ''))
              when 'a relationship' then 'relationship'
              when 'relationship' then 'relationship'
              when 'dating' then 'dating'
              when 'friendship' then 'friendship'
              when 'something casual' then 'casual'
              when 'casual' then 'casual'
              when 'still figuring it out' then 'exploring'
              when 'exploring' then 'exploring'
              else ''
            end = p_connection_goal
        )
      )
      and private.member_dating_community(v_viewer_id) is not null
      and (private.member_dating_community(candidate.id) =
          private.member_dating_community(v_viewer_id)
        or private.member_dating_community(candidate.id) is null)
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
  -- Rotate the capped candidate window every six hours per viewer. The previous
  -- UUID ordering permanently favoured the same first 100 accounts.
  order by
    pg_catalog.md5(
      v_viewer_id::text || ':' || candidate_id::text || ':' ||
      pg_catalog.floor(pg_catalog.date_part('epoch', pg_catalog.now()) / 21600)::bigint::text
    ),
    candidate_id
  limit greatest(1, least(coalesce(p_max_results, 100), 100));
end;
$function$;

-- Unassigned profiles may be viewed in either lane but cannot be interacted with.
create or replace function public.member_can_interact_with_discover_profile(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and target_user_id is not null
    and target_user_id <> auth.uid()
    and private.member_dating_community(auth.uid()) in ('lgbtq', 'straight')
    and private.member_dating_community(target_user_id) =
        private.member_dating_community(auth.uid())
    and public.can_interact_with_member(target_user_id) is true;
$function$;

revoke all on function public.member_can_interact_with_discover_profile(uuid)
  from public, anon;
grant execute on function public.member_can_interact_with_discover_profile(uuid)
  to authenticated;
comment on function public.member_can_interact_with_discover_profile(uuid) is
  'Returns only whether the signed-in member may interact with a Discover profile. Unassigned profiles are visible but always return false; orientation values are never exposed.';

commit;
