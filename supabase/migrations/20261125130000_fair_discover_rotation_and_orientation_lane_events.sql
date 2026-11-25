-- Fairly rotate Discover's capped candidate pool and align Events with
-- the same private, orientation-derived dating lane used by Discover/Nearby.
begin;

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
      -- Members are shown only others who explicitly selected the same private
      -- dating community. Community is never inferred from orientation or gender.
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

revoke all on function public.matchmaking_eligible_candidate_ids(
  double precision, integer, integer, text, text, text[], boolean, text, integer
) from public, anon;
grant execute on function public.matchmaking_eligible_candidate_ids(
  double precision, integer, integer, text, text, text[], boolean, text, integer
) to authenticated;

comment on function public.matchmaking_eligible_candidate_ids(
  double precision, integer, integer, text, text, text[], boolean, text, integer
) is
  'Returns only eligible candidate IDs from the orientation-derived dating lane. A viewer-specific six-hour hash rotation prevents the capped 100-member window from being permanently biased toward low UUIDs; reciprocal preferences, moderation, blocks, profile completeness, photos, and filters remain enforced.';

-- RLS policies run as the authenticated member, while the underlying
-- lane resolver remains private. This wrapper reveals only the caller's lane.
create or replace function public.current_member_dating_community()
returns text
language sql
stable
security definer
set search_path = ''
as $function$
  select private.member_dating_community(auth.uid());
$function$;
revoke all on function public.current_member_dating_community() from public, anon;
grant execute on function public.current_member_dating_community() to authenticated;

-- Reclassify existing events from each organiser's current private lane.
-- Drop the immutable-audience trigger only for this controlled migration backfill.
drop trigger if exists match_events_set_community on public.match_events;
update public.match_events event
set community = private.member_dating_community(event.organiser_id)
where private.member_dating_community(event.organiser_id) in ('lgbtq', 'straight');

create or replace function public.set_match_event_community()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  organiser_lane text;
begin
  if tg_op = 'INSERT' then
    organiser_lane := private.member_dating_community(new.organiser_id);
    if organiser_lane is null or organiser_lane not in ('lgbtq', 'straight') then
      raise exception 'Complete your private dating orientation before submitting an event.';
    end if;
    new.community := organiser_lane;
  else
    -- Keep an event's audience fixed after creation/reclassification.
    new.community := old.community;
  end if;
  return new;
end;
$function$;

revoke all on function public.set_match_event_community() from public, anon, authenticated;
create trigger match_events_set_community
before insert or update on public.match_events
for each row execute function public.set_match_event_community();

drop policy if exists "Published events and own submissions are visible" on public.match_events;
drop policy if exists "Members can view published events" on public.match_events;
drop policy if exists "Members can view published events in their own community" on public.match_events;
create policy "Members can view published events in their own orientation lane"
on public.match_events
for select to authenticated
using (
  (status = 'published'
    and community = public.current_member_dating_community())
  or organiser_id = (select auth.uid())
  or is_match_admin()
);

-- Keep event poster assets and ticket options behind the same lane boundary.
drop policy if exists "Members view permitted event poster assets" on public.match_event_poster_assets;
create policy "Members view permitted event poster assets"
on public.match_event_poster_assets
for select to authenticated
using (
  organiser_id = (select auth.uid())
  or is_match_admin()
  or exists (
    select 1 from public.match_events event
    where event.id = match_event_poster_assets.event_id
      and event.status = 'published'
      and event.community = public.current_member_dating_community()
  )
);

drop policy if exists "Members and organisers can view permitted ticket options" on public.match_event_ticket_types;
create policy "Members and organisers can view permitted ticket options"
on public.match_event_ticket_types
for select to authenticated
using (
  (
    is_active
    and exists (
      select 1 from public.match_events event
      where event.id = match_event_ticket_types.event_id
        and event.status = 'published'
        and event.community = public.current_member_dating_community()
    )
  )
  or exists (
    select 1 from public.match_events event
    where event.id = match_event_ticket_types.event_id
      and event.organiser_id = (select auth.uid())
      and event.status = 'pending_review'
  )
  or is_match_admin()
);

-- Responses and reports remain private to their owner; their event must also
-- belong to the member's current lane.
drop policy if exists "Members can respond privately to published events" on public.match_event_responses;
create policy "Members can respond privately to published events in their lane"
on public.match_event_responses
for insert to authenticated
with check (
  member_id = (select auth.uid())
  and exists (
    select 1 from public.match_events event
    where event.id = match_event_responses.event_id
      and event.status = 'published'
      and event.community = public.current_member_dating_community()
  )
);

drop policy if exists "Members can update only their own event response" on public.match_event_responses;
create policy "Members can update only their own event response in their lane"
on public.match_event_responses
for update to authenticated
using (member_id = (select auth.uid()))
with check (
  member_id = (select auth.uid())
  and exists (
    select 1 from public.match_events event
    where event.id = match_event_responses.event_id
      and event.status = 'published'
      and event.community = public.current_member_dating_community()
  )
);

drop policy if exists "Members can report published events" on public.match_event_reports;
create policy "Members can report published events in their lane"
on public.match_event_reports
for insert to authenticated
with check (
  reporter_id = (select auth.uid())
  and status = 'open'
  and admin_note is null
  and reviewed_by is null
  and reviewed_at is null
  and exists (
    select 1 from public.match_events event
    where event.id = match_event_reports.event_id
      and event.status = 'published'
      and event.community = public.current_member_dating_community()
  )
);

-- Published-event notifications go to members whose derived lane matches
-- the event, not only legacy records containing dating_community.
create or replace function public.notify_members_when_event_is_published()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if new.status = 'published' then
    if tg_op = 'INSERT' or old.status is distinct from 'published' then
      insert into public.notifications (
        user_id, type, title, body, related_user_id, is_read, action_url, action_label
      )
      select
        onboarding.user_id,
        'event_published',
        'New event posted',
        new.title || ' · ' || new.city,
        new.organiser_id,
        false,
        'event:' || new.id::text,
        'View event'
      from public.member_onboarding onboarding
      where onboarding.user_id <> new.organiser_id
        and private.member_dating_community(onboarding.user_id) = new.community;
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function public.notify_members_when_event_is_published()
  from public, anon, authenticated;

commit;
