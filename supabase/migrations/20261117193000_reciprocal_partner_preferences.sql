-- Add owner-private partner preferences and enforce them reciprocally in Discover.
begin;

alter table public.member_dating_details
  add column if not exists partner_preferences jsonb not null default '{}'::jsonb;

alter table public.member_dating_details
  add constraint member_dating_details_partner_preferences_object_check
  check (pg_catalog.jsonb_typeof(partner_preferences) = 'object');

create or replace function private.validate_partner_preferences()
returns trigger
language plpgsql
set search_path = ''
as $function$
declare
  preference record;
  allowed_values text[];
begin
  if pg_catalog.jsonb_typeof(coalesce(new.partner_preferences, '{}'::jsonb)) <> 'object' then
    raise exception 'Partner preferences must be an object' using errcode = '22023';
  end if;
  for preference in
    select key, value from pg_catalog.jsonb_each_text(coalesce(new.partner_preferences, '{}'::jsonb))
  loop
    case preference.key
      when 'smoking' then allowed_values := array['any','Never','Occasionally','Socially','Regularly','Prefer not to say'];
      when 'drinking' then allowed_values := array['any','Never','Occasionally','Socially','Regularly','Prefer not to say'];
      when 'activity_level' then allowed_values := array['any','Very active','Moderately active','Not very active','Prefer not to say'];
      when 'pets' then allowed_values := array['any','Have pets','Love pets','Want pets','Not for me','Prefer not to say'];
      when 'children' then allowed_values := array['any','Have children','Want children','Do not want children','Not sure','Prefer not to say'];
      when 'relationship_intention' then allowed_values := array['any','Long-term relationship','Dating','Friendship','Casual dating','Still figuring it out','Prefer not to say'];
      else
        raise exception 'Unsupported partner preference: %', preference.key using errcode = '22023';
    end case;
    if not (preference.value = any(allowed_values)) then
      raise exception 'Unsupported value for partner preference: %', preference.key using errcode = '22023';
    end if;
  end loop;
  new.partner_preferences := coalesce(new.partner_preferences, '{}'::jsonb);
  return new;
end;
$function$;

drop trigger if exists validate_partner_preferences on public.member_dating_details;
create trigger validate_partner_preferences
  before insert or update of partner_preferences on public.member_dating_details
  for each row execute function private.validate_partner_preferences();

revoke all on function private.validate_partner_preferences() from public, anon, authenticated;

-- Private, reciprocal lifestyle/relationship deal-breakers.
create or replace function private.member_meets_partner_preferences(
  p_viewer_id uuid,
  p_candidate_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(
    (
      select
        (coalesce(viewer.partner_preferences ->> 'smoking', 'any') = 'any'
          or viewer.partner_preferences ->> 'smoking' = candidate.smoking)
        and (coalesce(viewer.partner_preferences ->> 'drinking', 'any') = 'any'
          or viewer.partner_preferences ->> 'drinking' = candidate.drinking)
        and (coalesce(viewer.partner_preferences ->> 'activity_level', 'any') = 'any'
          or viewer.partner_preferences ->> 'activity_level' = candidate.activity_level)
        and (coalesce(viewer.partner_preferences ->> 'pets', 'any') = 'any'
          or viewer.partner_preferences ->> 'pets' = candidate.pets)
        and (coalesce(viewer.partner_preferences ->> 'children', 'any') = 'any'
          or viewer.partner_preferences ->> 'children' = candidate.children)
        and (coalesce(viewer.partner_preferences ->> 'relationship_intention', 'any') = 'any'
          or viewer.partner_preferences ->> 'relationship_intention' = candidate.relationship_intention)
      from public.member_dating_details viewer
      cross join public.member_dating_details candidate
      where viewer.user_id = p_viewer_id
        and candidate.user_id = p_candidate_id
    ),
    true
  );
$function$;

revoke all on function private.member_meets_partner_preferences(uuid, uuid)
  from public, anon, authenticated;

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
  double precision, integer, integer, text, text, text[], boolean, text, integer
) from public, anon;
grant execute on function public.matchmaking_eligible_candidate_ids(
  double precision, integer, integer, text, text, text[], boolean, text, integer
) to authenticated;

comment on column public.member_dating_details.partner_preferences is
  'Owner-private partner criteria. Applied reciprocally in server-side Discover eligibility; raw preferences are never returned to other members.';

commit;
