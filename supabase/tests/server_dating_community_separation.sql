\set ON_ERROR_STOP on

-- Explicit community labels are independent of sexual orientation and gender.
update public.member_onboarding
set answers = answers || '{"dating_community":"lgbtq"}'::jsonb
where user_id in (
  '00000000-0000-4000-8000-000000000001',
  '00000000-0000-4000-8000-000000000007',
  '00000000-0000-4000-8000-000000000010'
);
update public.member_onboarding
set answers = answers || '{"dating_community":"straight"}'::jsonb
where user_id in (
  '00000000-0000-4000-8000-000000000002',
  '00000000-0000-4000-8000-000000000003',
  '00000000-0000-4000-8000-000000000004',
  '00000000-0000-4000-8000-000000000005',
  '00000000-0000-4000-8000-000000000006',
  '00000000-0000-4000-8000-000000000008',
  '00000000-0000-4000-8000-000000000009',
  '00000000-0000-4000-8000-000000000011',
  '00000000-0000-4000-8000-000000000012'
);

-- Candidate 7 is heterosexual by orientation but explicitly joined LGBTQ+;
-- this verifies community is not inferred from orientation.
update public.member_onboarding
set answers = jsonb_set(answers, '{sexual_orientation}', '"Straight / heterosexual"')
where user_id = '00000000-0000-4000-8000-000000000007';

-- Make the two LGBTQ+ fixtures mutually compatible so this test isolates
-- community eligibility rather than unrelated partner-preference filters.
update public.profiles
set interested_in = 'All genders'
where id = '00000000-0000-4000-8000-000000000007';
insert into public.member_dating_details(user_id, partner_preferences)
values
  ('00000000-0000-4000-8000-000000000001', '{}'::jsonb),
  ('00000000-0000-4000-8000-000000000007', '{}'::jsonb)
on conflict (user_id) do update
set partner_preferences = '{}'::jsonb;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
do $community$
declare
  found_ids uuid[];
begin
  select array_agg(user_id order by user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids();

  if found_ids is distinct from array[
    '00000000-0000-4000-8000-000000000007'::uuid,
    '00000000-0000-4000-8000-000000000010'::uuid
  ] then
    raise exception 'LGBTQ+ viewer should see only LGBTQ+ candidates, regardless of orientation; got %', found_ids;
  end if;

  if public.can_interact_with_member('00000000-0000-4000-8000-000000000002') then
    raise exception 'LGBTQ+ viewer must not interact with a Straight member';
  end if;
  if not public.can_interact_with_member('00000000-0000-4000-8000-000000000007') then
    raise exception 'LGBTQ+ viewer should interact with a compatible LGBTQ+ member';
  end if;

  if private.can_view_story_from_owner('00000000-0000-4000-8000-000000000002') then
    raise exception 'Everyone Story access must reject a member from the other community';
  end if;
  if not private.can_view_story_from_owner('00000000-0000-4000-8000-000000000007') then
    raise exception 'Everyone Story access should allow a compatible same-community member';
  end if;
end;
$community$;

-- Reverse direction: a Straight member must never see LGBTQ+ candidates.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
do $straight$
declare
  found_ids uuid[];
begin
  select array_agg(user_id order by user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids();

  if found_ids is distinct from array['00000000-0000-4000-8000-000000000003'::uuid] then
    raise exception 'Straight viewer should see only Straight candidates; got %', found_ids;
  end if;
end;
$straight$;

-- The database trigger rejects cross-community likes even if a client bypasses UI.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
set role authenticated;
do $likes$
begin
  begin
    insert into public.likes(liker_id, liked_id)
    values (auth.uid(), '00000000-0000-4000-8000-000000000002');
    raise exception 'Cross-community like unexpectedly succeeded';
  exception when check_violation then
    null;
  end;

  insert into public.likes(liker_id, liked_id)
  values (auth.uid(), '00000000-0000-4000-8000-000000000007');
end;
$likes$;
reset role;

select 'strict dating community separation tests passed' as result;
