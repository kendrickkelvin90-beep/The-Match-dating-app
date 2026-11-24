\set ON_ERROR_STOP on

-- Legacy community values are retained for compatibility, but a disclosed
-- sexual orientation now determines the member's dating lane automatically.
update public.member_onboarding
set answers = answers || '{"dating_community":"straight"}'::jsonb
where user_id in (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000003',
  '00000000-0000-4000-8000-000000000004',
  '00000000-0000-4000-8000-000000000005',
  '00000000-0000-4000-8000-000000000006',
  '00000000-0000-4000-8000-000000000007',
  '00000000-0000-4000-8000-000000000008',
  '00000000-0000-4000-8000-000000000009',
  '00000000-0000-4000-8000-000000000010',
  '00000000-0000-4000-8000-000000000011',
  '00000000-0000-4000-8000-000000000012'
);

-- User 1's saved legacy label says straight, but their current orientation
-- places them in LGBTQ+. User 7's old label says straight too, and their
-- straight orientation keeps them in the straight lane. Orientation wins.
update public.member_onboarding
set answers = jsonb_set(answers, '{sexual_orientation}', '"Bisexual"')
where user_id = '00000000-0000-4000-8000-000000000001';

update public.member_onboarding
set answers = jsonb_set(answers, '{sexual_orientation}', '"Straight / heterosexual"')
where user_id = '00000000-0000-4000-8000-000000000007';

-- A new member with an orientation but no legacy dating_community choice is
-- assigned automatically; no additional community selection is required.
update public.member_onboarding
set answers = (answers - 'dating_community')
where user_id = '00000000-0000-4000-8000-000000000013';

do $lane_assignment$
begin
  if private.member_dating_community('00000000-0000-4000-8000-000000000001') <> 'lgbtq' then
    raise exception 'Bisexual orientation must automatically place the member in the LGBTQ+ lane';
  end if;
  if private.member_dating_community('00000000-0000-4000-8000-000000000007') <> 'straight' then
    raise exception 'Straight orientation must automatically place the member in the straight lane';
  end if;
  if private.member_dating_community('00000000-0000-4000-8000-000000000013') <> 'straight' then
    raise exception 'A new member must be assigned from orientation without a dating_community answer';
  end if;
end;
$lane_assignment$;

-- Explicitly cover the agreed undisclosed-orientation behavior:
-- legacy members keep their saved lane, while new undisclosed members are
-- not guessed into either dating lane.
insert into public.member_onboarding(user_id, answers)
values
  ('00000000-0000-4000-8000-000000000014', '{"sexual_orientation":"Prefer not to say","dating_community":"lgbtq"}'::jsonb),
  ('00000000-0000-4000-8000-000000000015', '{"sexual_orientation":"Prefer not to say"}'::jsonb)
on conflict (user_id) do update set answers = excluded.answers;

do $undisclosed_orientation$
begin
  if private.member_dating_community('00000000-0000-4000-8000-000000000014') <> 'lgbtq' then
    raise exception 'An existing undisclosed member must retain their saved legacy lane';
  end if;
  if private.member_dating_community('00000000-0000-4000-8000-000000000015') is not null then
    raise exception 'A new undisclosed member must not be guessed into either dating lane';
  end if;
end;
$undisclosed_orientation$;

-- Make the fixture deterministic even when this SQL test is run after
-- other regression files in the same disposable database.
delete from public.likes
where liker_id in (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000010'
)
or liked_id in (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000010'
);

delete from public.messages
where sender_id in (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000010'
)
or receiver_id in (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000010'
);

-- Keep the two LGBTQ+ fixtures mutually compatible so this test isolates
-- lane eligibility rather than unrelated partner-preference filters.
update public.profiles
set interested_in = 'All genders'
where id = '00000000-0000-4000-8000-000000000010';

insert into public.member_dating_details(user_id, partner_preferences)
values
  ('00000000-0000-4000-8000-000000000001', '{}'::jsonb),
  ('00000000-0000-4000-8000-000000000010', '{}'::jsonb)
on conflict (user_id) do update
set partner_preferences = '{}'::jsonb;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
do $lgbtq_lane$
declare
  found_ids uuid[];
begin
  select array_agg(user_id order by user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids();

  if found_ids is distinct from array['00000000-0000-4000-8000-000000000010'::uuid] then
    raise exception 'LGBTQ+ viewer should see compatible LGBTQ+ candidates only; got %', found_ids;
  end if;

  if public.can_interact_with_member('00000000-0000-4000-8000-000000000002') then
    raise exception 'A new cross-lane interaction must be rejected';
  end if;
  if not public.can_interact_with_member('00000000-0000-4000-8000-000000000010') then
    raise exception 'A compatible same-lane member should be interactable';
  end if;

  if private.can_view_story_from_owner('00000000-0000-4000-8000-000000000002') then
    raise exception 'Everyone Stories must not cross dating lanes';
  end if;
  if not private.can_view_story_from_owner('00000000-0000-4000-8000-000000000010') then
    raise exception 'Everyone Stories should allow a compatible member in the same lane';
  end if;
end;
$lgbtq_lane$;

-- Reverse direction: a straight member sees only compatible straight members.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
do $straight_lane$
declare
  found_ids uuid[];
begin
  select array_agg(user_id order by user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids();

  if found_ids is distinct from array['00000000-0000-4000-8000-000000000003'::uuid] then
    raise exception 'Straight viewer should see straight candidates only; got %', found_ids;
  end if;
end;
$straight_lane$;

-- Even a direct authenticated insert cannot bypass the lane boundary or
-- reciprocal gender-preference checks.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
set role authenticated;
do $likes$
begin
  begin
    insert into public.likes(liker_id, liked_id)
    values (auth.uid(), '00000000-0000-4000-8000-000000000002');
    raise exception 'Cross-lane like unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  insert into public.likes(liker_id, liked_id)
  values (auth.uid(), '00000000-0000-4000-8000-000000000010');
end;
$likes$;

do $passes$
begin
  begin
    insert into public.profile_passes(passer_id, passed_id)
    values (auth.uid(), '00000000-0000-4000-8000-000000000002');
    raise exception 'Cross-lane pass unexpectedly succeeded';
  exception when check_violation then
    null;
  end;
end;
$passes$;
reset role;

-- Shared dating details use the same derived lane and reciprocal
-- compatibility rules as Discover; a caller cannot request cross-lane details.
update public.member_dating_details
set share_interests = true
where user_id = '00000000-0000-4000-8000-000000000010';

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
do $shared_details$
declare
  visible_ids uuid[];
begin
  select array_agg(user_id order by user_id)
    into visible_ids
  from public.get_shared_dating_details(array[
    '00000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000010'::uuid
  ]);

  if visible_ids is distinct from array['00000000-0000-4000-8000-000000000010'::uuid] then
    raise exception 'Shared dating details must stay within the compatible dating lane; got %', visible_ids;
  end if;
end;
$shared_details$;

-- Existing conversations survive a later lane classification change, while
-- they do not make either member visible in the other's new Discover lane.
insert into public.messages(sender_id, receiver_id, body)
values (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000002',
  'Existing conversation preserved'
);

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
do $existing_connection$
begin
  if not public.can_interact_with_member('00000000-0000-4000-8000-000000000002') then
    raise exception 'Existing cross-lane conversation must remain accessible';
  end if;
  if exists (
    select 1
    from public.discover_profiles_secure()
    where id = '00000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'An existing conversation must not put a cross-lane member into Discover';
  end if;
end;
$existing_connection$;

select 'orientation-derived separated dating lane tests passed' as result;
