-- Strictly separate Straight and LGBTQ+ dating communities.
-- Community is an explicit private choice, independent of sexual orientation
-- and gender identity. Discover, Everyone Stories and likes enforce it server-side.
begin;

create or replace function private.member_dating_community(p_user_id uuid)
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select case
    when onboarding.answers ->> 'dating_community' in ('straight', 'lgbtq')
      then onboarding.answers ->> 'dating_community'
    else null
  end
  from public.member_onboarding onboarding
  where onboarding.user_id = p_user_id;
$function$;
revoke all on function private.member_dating_community(uuid) from public, anon;
grant usage on schema private to authenticated;
grant execute on function private.member_dating_community(uuid) to authenticated;

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
      -- A straight member is shown only other members who explicitly selected
      -- Straight / heterosexual. No orientation is inferred from gender.
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
      and private.member_dating_community(candidate.id) =
          private.member_dating_community(v_viewer_id)
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

create or replace function private.can_view_story_from_owner(p_owner_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select
    auth.uid() is not null
    and p_owner_id is not null
    and p_owner_id <> auth.uid()
    and exists (
      select 1
      from public.profiles viewer
      join public.profiles owner on owner.id = p_owner_id
      join public.member_onboarding viewer_onboarding on viewer_onboarding.user_id = viewer.id
      join public.member_onboarding owner_onboarding on owner_onboarding.user_id = owner.id
      where viewer.id = auth.uid()
        and public.is_match_profile_complete(viewer.id)
        and public.is_match_profile_complete(owner.id)
        and viewer.age >= 18
        and owner.age >= 18
        and private.match_preference_accepts_gender(viewer.interested_in, owner.gender_identity)
        and private.match_preference_accepts_gender(owner.interested_in, viewer.gender_identity)
        and private.member_meets_partner_preferences(viewer.id, owner.id)
        and private.member_meets_partner_preferences(owner.id, viewer.id)
        and private.member_dating_community(viewer.id) is not null
        and private.member_dating_community(owner.id) =
            private.member_dating_community(viewer.id)
        and (select count(*) from public.profile_photos viewer_photo where viewer_photo.user_id = viewer.id) >= 2
        and (select count(*) from public.profile_photos owner_photo where owner_photo.user_id = owner.id) >= 2
        and not exists (
          select 1 from public.member_blocks block_record
          where (block_record.blocker_id = viewer.id and block_record.blocked_id = owner.id)
             or (block_record.blocker_id = owner.id and block_record.blocked_id = viewer.id)
        )
        and not exists (
          select 1 from public.member_moderation moderation
          where moderation.user_id in (viewer.id, owner.id)
            and (
              moderation.status = 'banned'
              or (moderation.status = 'suspended' and moderation.expires_at > now())
            )
        )
    );
$function$;

-- All app interaction paths (chat, likes, passes, match-only Stories and
-- reaction access) share this guard, so a previously-created cross-community
-- connection cannot continue interacting after this migration.
create or replace function public.can_interact_with_member(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and target_user_id is not null
    and target_user_id <> auth.uid()
    and not exists (
      select 1
      from public.member_moderation moderation
      where moderation.user_id in (auth.uid(), target_user_id)
        and (
          moderation.status = 'banned'
          or (moderation.status = 'suspended' and moderation.expires_at > now())
        )
    )
    and private.member_dating_community(auth.uid()) is not null
    and private.member_dating_community(target_user_id) =
        private.member_dating_community(auth.uid())
    and not exists (
      select 1
      from public.member_blocks block_record
      where (block_record.blocker_id = auth.uid() and block_record.blocked_id = target_user_id)
         or (block_record.blocker_id = target_user_id and block_record.blocked_id = auth.uid())
    );
$function$;
revoke all on function public.can_interact_with_member(uuid) from public, anon;
grant execute on function public.can_interact_with_member(uuid) to authenticated;

create or replace function private.enforce_same_dating_community_on_like()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_liker_community text;
  v_liked_community text;
begin
  v_liker_community := private.member_dating_community(new.liker_id);
  v_liked_community := private.member_dating_community(new.liked_id);
  if v_liker_community is null or v_liked_community is null then
    raise exception 'Both members must choose a dating community before liking profiles.'
      using errcode = '23514';
  end if;
  if v_liker_community <> v_liked_community then
    raise exception 'You can only like members in your own dating community.'
      using errcode = '23514';
  end if;
  return new;
end;
$function$;

drop trigger if exists enforce_same_dating_community_on_like on public.likes;
create trigger enforce_same_dating_community_on_like
before insert or update of liker_id, liked_id on public.likes
for each row execute function private.enforce_same_dating_community_on_like();
revoke all on function private.enforce_same_dating_community_on_like() from public, anon, authenticated;

comment on function private.member_dating_community(uuid) is
  'Returns a member''s private self-selected dating community (straight or lgbtq); null means they have not selected one.';
comment on function private.enforce_same_dating_community_on_like() is
  'Blocks cross-community likes and requires both members to choose a community.';

commit;
