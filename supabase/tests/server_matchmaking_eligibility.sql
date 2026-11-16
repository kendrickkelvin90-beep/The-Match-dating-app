\set ON_ERROR_STOP on

insert into public.profiles
  (id, display_name, gender_identity, interested_in, bio, city, age, is_verified, sexual_roles, verification_level)
values
  ('00000000-0000-4000-8000-000000000001', 'Viewer', 'Man', 'All genders', 'A complete viewer profile', 'Lagos', 30, false, array['Bottom'], 'none'),
  ('00000000-0000-4000-8000-000000000002', 'Candidate', 'Man', 'Men', 'A complete candidate profile', 'Lagos', 27, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000003', 'Blocked', 'Man', 'Men', 'A complete candidate profile', 'Lagos', 27, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000004', 'Suspended', 'Man', 'Men', 'A complete candidate profile', 'Lagos', 27, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000005', 'Banned', 'Man', 'Men', 'A complete candidate profile', 'Lagos', 27, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000006', 'Incomplete', 'Man', 'Men', '', 'Lagos', 27, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000007', 'Verified', 'Woman', 'Men', 'A complete verified profile', 'Abuja', 28, true, array['Bottom'], 'basic'),
  ('00000000-0000-4000-8000-000000000008', 'Member', 'Man', 'Men', 'A placeholder profile bio', 'Lagos', 28, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000009', 'No Primary Photo', 'Man', 'Men', 'A complete profile without its primary photo', 'Lagos', 28, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000010', 'No Role', 'Man', 'All genders', 'A complete profile with no role selected', 'Lagos', 29, false, array[]::text[], 'none'),
  ('00000000-0000-4000-8000-000000000011', 'One-way mismatch A', 'Man', 'Women', 'A complete profile with a one-way preference', 'Lagos', 29, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000012', 'One-way mismatch B', 'Woman', 'Women', 'A complete profile with a one-way preference', 'Lagos', 29, false, array['Bottom'], 'none'),
  ('00000000-0000-4000-8000-000000000013', 'Underage test account', 'Man', 'Women', 'An underage account must never become discoverable', 'Lagos', null, false, array[]::text[], 'none');

insert into public.member_onboarding (user_id, answers)
values
  ('00000000-0000-4000-8000-000000000001', '{"sexual_orientation":"Straight / heterosexual","relationship_goal":"A relationship"}'),
  ('00000000-0000-4000-8000-000000000002', '{"sexual_orientation":"Straight / heterosexual","relationship_goal":"A relationship"}'),
  ('00000000-0000-4000-8000-000000000003', '{"sexual_orientation":"Straight / heterosexual","relationship_goal":"A relationship"}'),
  ('00000000-0000-4000-8000-000000000004', '{"sexual_orientation":"Straight / heterosexual","relationship_goal":"A relationship"}'),
  ('00000000-0000-4000-8000-000000000005', '{"sexual_orientation":"Straight / heterosexual","relationship_goal":"A relationship"}'),
  ('00000000-0000-4000-8000-000000000006', '{"sexual_orientation":"Straight / heterosexual","relationship_goal":"A relationship"}'),
  ('00000000-0000-4000-8000-000000000007', '{"sexual_orientation":"Straight / heterosexual","relationship_goal":"A relationship"}'),
  ('00000000-0000-4000-8000-000000000008', '{"sexual_orientation":"Straight / heterosexual","relationship_goal":"A relationship"}'),
  ('00000000-0000-4000-8000-000000000009', '{"sexual_orientation":"Straight / heterosexual","relationship_goal":"A relationship"}'),
  ('00000000-0000-4000-8000-000000000010', '{"sexual_orientation":"Bisexual","relationship_goal":"A relationship"}'),
  ('00000000-0000-4000-8000-000000000011', '{"sexual_orientation":"Straight / heterosexual","relationship_goal":"A relationship"}'),
  ('00000000-0000-4000-8000-000000000012', '{"sexual_orientation":"Straight / heterosexual","relationship_goal":"A relationship"}'),
  ('00000000-0000-4000-8000-000000000013', '{"sexual_orientation":"Straight / heterosexual","relationship_goal":"A relationship"}');

insert into public.profile_photos (user_id, storage_path, position)
select ids.user_id, ids.user_id::text || '-' || photo_no::text,
       case when ids.user_id = '00000000-0000-4000-8000-000000000009'::uuid then photo_no else photo_no - 1 end
from (values
  ('00000000-0000-4000-8000-000000000001'::uuid),
  ('00000000-0000-4000-8000-000000000002'::uuid),
  ('00000000-0000-4000-8000-000000000003'::uuid),
  ('00000000-0000-4000-8000-000000000004'::uuid),
  ('00000000-0000-4000-8000-000000000005'::uuid),
  ('00000000-0000-4000-8000-000000000006'::uuid),
  ('00000000-0000-4000-8000-000000000007'::uuid),
  ('00000000-0000-4000-8000-000000000008'::uuid),
  ('00000000-0000-4000-8000-000000000009'::uuid),
  ('00000000-0000-4000-8000-000000000010'::uuid),
  ('00000000-0000-4000-8000-000000000011'::uuid),
  ('00000000-0000-4000-8000-000000000012'::uuid),
  ('00000000-0000-4000-8000-000000000013'::uuid)
) ids(user_id)
cross join generate_series(1,2) photo_no;

insert into public.member_blocks values
  ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003');
insert into public.member_moderation (user_id, status, reason, expires_at) values
  ('00000000-0000-4000-8000-000000000004','suspended','Test suspension',now()+interval '1 day'),
  ('00000000-0000-4000-8000-000000000005','banned','Test permanent ban',null);
insert into public.premium_memberships values
  ('00000000-0000-4000-8000-000000000001',now()+interval '30 days');

-- Keep the synthetic JWT claim at session scope across separate SQL commands.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);

do $$
declare
  found_ids uuid[];
begin
  -- Empty role selections must be valid for both viewers and candidates.
  update public.profiles
  set sexual_roles = '{}'::text[]
  where id = '00000000-0000-4000-8000-000000000001';

  if not public.is_match_profile_complete('00000000-0000-4000-8000-000000000001') then
    raise exception 'A viewer with no role preference must still have a complete profile';
  end if;

  begin
    update public.profiles
    set age = 17
    where id = '00000000-0000-4000-8000-000000000013';
    raise exception 'The database unexpectedly accepted an under-18 profile age';
  exception when check_violation then
    null;
  end;

  if (select age from public.profiles where id = '00000000-0000-4000-8000-000000000013') is not null then
    raise exception 'The under-18 profile age was persisted despite the database guard';
  end if;

  if public.is_match_profile_complete('00000000-0000-4000-8000-000000000013') then
    raise exception 'An account under 18 must never qualify as a complete dating profile';
  end if;

  select array_agg(user_id order by user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids();

  if found_ids is distinct from array[
    '00000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000007'::uuid
  ] then
    raise exception 'Expected only complete, active, unblocked candidates; got %', found_ids;
  end if;

  select array_agg(user_id order by user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids(p_connection_goal => 'relationship');
  if found_ids is distinct from array[
    '00000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000007'::uuid
  ] then
    raise exception 'Straight connection-goal filtering returned unexpected candidates: %', found_ids;
  end if;

  select array_agg(user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids(p_connection_goal => 'dating');
  if found_ids is not null then
    raise exception 'Connection-goal filter should exclude candidates with a different stated goal: %', found_ids;
  end if;

  select array_agg(user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids(p_show_me => 'women');
  if found_ids is distinct from array['00000000-0000-4000-8000-000000000007'::uuid] then
    raise exception 'Gender filter did not return the expected candidate: %', found_ids;
  end if;

  select array_agg(user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids(p_role_preferences => array['Bottom']);
  if found_ids is distinct from array['00000000-0000-4000-8000-000000000007'::uuid] then
    raise exception 'Role filter did not return the expected candidate: %', found_ids;
  end if;

  select array_agg(user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids(p_verified_only => true);
  if found_ids is distinct from array['00000000-0000-4000-8000-000000000007'::uuid] then
    raise exception 'Verified-only filter did not return the expected candidate: %', found_ids;
  end if;

  select array_agg(user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids(p_city => 'Abuja');
  if found_ids is distinct from array['00000000-0000-4000-8000-000000000007'::uuid] then
    raise exception 'City filter did not preserve the production Discover result: %', found_ids;
  end if;

  select array_agg(user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids(p_max_distance_km => 5);
  if found_ids is distinct from array['00000000-0000-4000-8000-000000000002'::uuid] then
    raise exception 'Distance filter did not preserve the production Discover result: %', found_ids;
  end if;
  -- A bisexual viewer can discover straight and bisexual members; the
  -- straight-only audience gate is not applied to bisexual members.
  update public.member_onboarding
  set answers = jsonb_set(answers, '{sexual_orientation}', '"Bisexual"')
  where user_id = '00000000-0000-4000-8000-000000000001';

  select array_agg(user_id order by user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids();

  if found_ids is distinct from array[
    '00000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000007'::uuid,
    '00000000-0000-4000-8000-000000000010'::uuid
  ] then
    raise exception 'Bisexual members should retain access to compatible straight and bisexual members: %', found_ids;
  end if;

  if not private.match_preference_accepts_gender('Men and women', 'Man')
     or not private.match_preference_accepts_gender('Men and women', 'Woman')
     or private.match_preference_accepts_gender('Men and women', 'Non-binary')
     or not private.match_preference_accepts_gender('Men', 'Trans man')
     or private.match_preference_accepts_gender('Men', 'Woman')
     or not private.match_preference_accepts_gender('Women', 'Trans woman')
     or private.match_preference_accepts_gender('Women', 'Man')
     or not private.match_preference_accepts_gender('All genders', 'Non-binary')
     or not private.match_preference_accepts_gender('Non-binary people', 'Non-binary')
     or private.match_preference_accepts_gender('Men', 'Genderqueer') then
    raise exception 'Mutual gender-preference helper returned an unexpected result';
  end if;
end;
$$;

-- Direct table access must remain owner-only; shared data is exposed only
-- through the explicit opt-in RPC tested below.
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
do $$
begin
  if exists (
    select 1 from public.member_dating_details
    where user_id = '00000000-0000-4000-8000-000000000002'
  ) then
    raise exception 'A member can directly read another member''s private dating details';
  end if;
end;
$$;
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);

insert into public.member_dating_details
  (user_id, interests, smoking, drinking, activity_level, pets, children, share_interests, share_lifestyle)
values
  ('00000000-0000-4000-8000-000000000001', array['Music','Travel','Football'], 'Prefer not to say', 'Prefer not to say', 'Prefer not to say', 'Prefer not to say', 'Prefer not to say', false, false),
  ('00000000-0000-4000-8000-000000000002', array['Music','Travel'], 'Never', 'Socially', 'Very active', 'Love pets', 'Not sure', true, false),
  ('00000000-0000-4000-8000-000000000003', array['Gaming'], 'Never', 'Never', 'Moderately active', 'Not for me', 'Not sure', true, false),
  ('00000000-0000-4000-8000-000000000007', array['Football'], 'Socially', 'Occasionally', 'Moderately active', 'Have pets', 'Have children', true, true),
  ('00000000-0000-4000-8000-000000000010', array['Travel'], 'Never', 'Never', 'Moderately active', 'Prefer not to say', 'Not sure', false, true),
  ('00000000-0000-4000-8000-000000000011', array['Gaming'], 'Never', 'Never', 'Moderately active', 'Prefer not to say', 'Not sure', true, false),
  ('00000000-0000-4000-8000-000000000012', array['Music'], 'Never', 'Never', 'Moderately active', 'Prefer not to say', 'Not sure', true, false);

do $$
declare
  shared_row record;
begin
  if (select count(*) from public.get_shared_dating_details(array[
        '00000000-0000-4000-8000-000000000002'::uuid,
        '00000000-0000-4000-8000-000000000003'::uuid,
        '00000000-0000-4000-8000-000000000007'::uuid,
        '00000000-0000-4000-8000-000000000010'::uuid,
        '00000000-0000-4000-8000-000000000011'::uuid,
        '00000000-0000-4000-8000-000000000012'::uuid
      ])) <> 3 then
    raise exception 'Only mutually compatible, unblocked members may expose shared dating details';
  end if;

  if exists (
    select 1 from public.get_shared_dating_details(array[
      '00000000-0000-4000-8000-000000000011'::uuid,
      '00000000-0000-4000-8000-000000000012'::uuid
    ])
  ) then
    raise exception 'One-way gender-preference mismatches must not expose shared dating details';
  end if;

  update public.member_onboarding
  set answers = jsonb_set(answers, '{sexual_orientation}', '"Straight / heterosexual"')
  where user_id = '00000000-0000-4000-8000-000000000001';

  if exists (
    select 1 from public.get_shared_dating_details(array[
      '00000000-0000-4000-8000-000000000010'::uuid
    ])
  ) then
    raise exception 'Straight members must not receive shared details from non-straight candidates';
  end if;

  update public.member_onboarding
  set answers = jsonb_set(answers, '{sexual_orientation}', '"Bisexual"')
  where user_id = '00000000-0000-4000-8000-000000000001';

  select * into shared_row
  from public.get_shared_dating_details(array[
    '00000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000007'::uuid
  ])
  where user_id = '00000000-0000-4000-8000-000000000002';

  if shared_row.interests is distinct from array['Music','Travel']::text[]
     or shared_row.smoking is not null
     or shared_row.drinking is not null then
    raise exception 'Interest-only sharing must not expose lifestyle details';
  end if;

  select * into shared_row
  from public.get_shared_dating_details(array[
    '00000000-0000-4000-8000-000000000007'::uuid
  ])
  where user_id = '00000000-0000-4000-8000-000000000007';

  if shared_row.interests is distinct from array['Football']::text[]
     or shared_row.smoking is distinct from 'Socially'
     or shared_row.children is distinct from 'Have children' then
    raise exception 'Opted-in lifestyle details were not returned correctly';
  end if;
end;
$$;

do $$
declare
  score_row record;
  score_count integer;
begin
  select count(*) into score_count
  from public.get_interest_match_scores(array[
    '00000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-4000-8000-000000000007'::uuid,
    '00000000-0000-4000-8000-000000000010'::uuid,
    '00000000-0000-4000-8000-000000000011'::uuid,
    '00000000-0000-4000-8000-000000000012'::uuid
  ]);
  if score_count <> 2 then
    raise exception 'Only visible members who opted into interest sharing should receive scores; got %', score_count;
  end if;

  select * into score_row
  from public.get_interest_match_scores(array['00000000-0000-4000-8000-000000000002'::uuid])
  where user_id = '00000000-0000-4000-8000-000000000002';
  if score_row.shared_interest_count <> 2 or score_row.interest_match_percent <> 67 then
    raise exception 'Expected 2 shared interests and 67 percent overlap; got % / %',
      score_row.shared_interest_count, score_row.interest_match_percent;
  end if;

  select * into score_row
  from public.get_interest_match_scores(array['00000000-0000-4000-8000-000000000007'::uuid])
  where user_id = '00000000-0000-4000-8000-000000000007';
  if score_row.shared_interest_count <> 1 or score_row.interest_match_percent <> 33 then
    raise exception 'Expected 1 shared interest and 33 percent overlap; got % / %',
      score_row.shared_interest_count, score_row.interest_match_percent;
  end if;

  if exists (
    select 1 from public.get_interest_match_scores(array['00000000-0000-4000-8000-000000000010'::uuid])
  ) then
    raise exception 'Lifestyle-only sharing must not enable interest matching scores';
  end if;
end;
$$;

-- Insert the viewer's moderation row explicitly; the fixture initially only
-- contains moderation rows for the suspended and banned candidate accounts.
insert into public.member_moderation (user_id, status, reason, expires_at)
values (
  '00000000-0000-4000-8000-000000000001',
  'suspended',
  'Test viewer suspension',
  now()+interval '1 day'
)
on conflict (user_id) do update
set status = excluded.status,
    expires_at = excluded.expires_at;

do $$
declare
  found_ids uuid[];
begin
  select array_agg(user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids();

  if found_ids is not null then
    raise exception 'Suspended viewer must not receive candidates: %', found_ids;
  end if;

  perform set_config('request.jwt.claim.sub','',false);
  begin
    perform * from public.matchmaking_eligible_candidate_ids();
    raise exception 'Unauthenticated call unexpectedly succeeded';
  exception when sqlstate '28000' then
    null;
  end;
end;
$$;

do $$
begin
  if has_function_privilege(
    'anon',
    'public.matchmaking_eligible_candidate_ids(double precision,integer,integer,text,text,text[],boolean,text,integer)',
    'EXECUTE'
  ) then
    raise exception 'Anonymous role must not execute the eligibility function';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.matchmaking_eligible_candidate_ids(double precision,integer,integer,text,text,text[],boolean,text,integer)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated role must be able to execute the eligibility function';
  end if;
end;
$$;

do $$
begin
  if has_function_privilege(
    'anon',
    'public.get_interest_match_scores(uuid[])',
    'EXECUTE'
  ) then
    raise exception 'Anonymous role must not execute interest compatibility scoring';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.get_interest_match_scores(uuid[])',
    'EXECUTE'
  ) then
    raise exception 'Authenticated role must execute interest compatibility scoring';
  end if;
end;
$$;


-- The viewer's own dating preferences remain private while scoring candidates.
update public.member_dating_details
set relationship_intention = 'Long-term relationship',
    communication_style = 'Deep conversations',
    languages = array['English','Yoruba']
where user_id = '00000000-0000-4000-8000-000000000001';

-- Optional dating profile extras remain private unless the member opts in.
update public.member_dating_details
set relationship_intention = 'Long-term relationship',
    communication_style = 'Deep conversations',
    languages = array['English','Yoruba'],
    education_level = 'Undergraduate',
    occupation = 'Designer',
    favorite_music = 'Afrobeats',
    favorite_movies = 'Comedy',
    favorite_food = 'Jollof rice',
    share_profile_extras = true
where user_id = '00000000-0000-4000-8000-000000000002';

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
do $$
declare
  extras_row record;
begin
  select * into extras_row
  from public.get_shared_profile_extras(array[
    '00000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-4000-8000-000000000010'::uuid
  ])
  where user_id = '00000000-0000-4000-8000-000000000002';

  if extras_row.relationship_intention <> 'Long-term relationship'
     or extras_row.communication_style <> 'Deep conversations'
     or extras_row.languages is distinct from array['English','Yoruba']::text[]
     or extras_row.occupation <> 'Designer'
     or extras_row.favorite_food <> 'Jollof rice' then
    raise exception 'Opted-in dating profile extras were not returned correctly';
  end if;

  if (select count(*) from public.get_shared_profile_extras(array[
    '00000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000003'::uuid,
    '00000000-0000-4000-8000-000000000010'::uuid
  ])) <> 1 then
    raise exception 'Only the member who opted in should expose profile extras';
  end if;
end;
$$;

do $$
begin
  begin
    update public.member_dating_details
    set languages = array['English','Yoruba','Igbo','Hausa','French','Spanish','Arabic','German','Portuguese']
    where user_id = '00000000-0000-4000-8000-000000000002';
    raise exception 'More than eight languages unexpectedly passed validation';
  exception when sqlstate '22023' then
    null;
  end;
end;
$$;

do $$
declare
  compatibility_row record;
begin
  select * into compatibility_row
  from public.get_dating_compatibility_scores(array[
    '00000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000007'::uuid,
    '00000000-0000-4000-8000-000000000010'::uuid
  ])
  where user_id = '00000000-0000-4000-8000-000000000002';

  if compatibility_row.compatibility_percent <> 83
     or compatibility_row.scored_dimensions <> 4
     or compatibility_row.shared_interest_count <> 2
     or compatibility_row.interest_match_percent <> 67
     or compatibility_row.relationship_intention_match is distinct from true
     or compatibility_row.communication_style_match is distinct from true
     or compatibility_row.shared_language_count <> 2 then
    raise exception 'Explainable compatibility score did not match the opted-in fixture data';
  end if;

  select * into compatibility_row
  from public.get_dating_compatibility_scores(array[
    '00000000-0000-4000-8000-000000000007'::uuid
  ])
  where user_id = '00000000-0000-4000-8000-000000000007';

  if compatibility_row.scored_dimensions <> 1
     or compatibility_row.compatibility_percent <> 33 then
    raise exception 'Interest-only compatibility should use only the available opted-in dimension';
  end if;

  if exists (
    select 1 from public.get_dating_compatibility_scores(array[
      '00000000-0000-4000-8000-000000000010'::uuid
    ])
  ) then
    raise exception 'Lifestyle-only consent must not expose or score unshared profile details';
  end if;
end;
$$;

do $$
begin
  if has_function_privilege('anon','public.get_dating_compatibility_scores(uuid[])','EXECUTE') then
    raise exception 'Anonymous role must not execute compatibility scoring';
  end if;
  if not has_function_privilege('authenticated','public.get_dating_compatibility_scores(uuid[])','EXECUTE') then
    raise exception 'Authenticated role must execute compatibility scoring';
  end if;
end;
$$;

do $$
begin
  if has_function_privilege('anon','public.get_shared_profile_extras(uuid[])','EXECUTE') then
    raise exception 'Anonymous role must not execute shared profile extras RPC';
  end if;
  if not has_function_privilege('authenticated','public.get_shared_profile_extras(uuid[])','EXECUTE') then
    raise exception 'Authenticated role must execute shared profile extras RPC';
  end if;
end;
$$;

-- Private Realtime typing is limited to the two members in the topic.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
select set_config(
  'request.realtime.topic',
  'match-typing:00000000-0000-4000-8000-000000000001:00000000-0000-4000-8000-000000000002',
  false
);
set role authenticated;
insert into realtime.messages(topic, extension, payload)
values (
  'match-typing:00000000-0000-4000-8000-000000000001:00000000-0000-4000-8000-000000000002',
  'broadcast',
  jsonb_build_object(
    'event','typing',
    'payload',jsonb_build_object(
      'user_id','00000000-0000-4000-8000-000000000001',
      'is_typing',true
    )
  )
);

do $$
begin
  if not exists (
    select 1 from realtime.messages
    where topic = realtime.topic()
  ) then
    raise exception 'An authorised member could not read their conversation typing channel';
  end if;

  begin
    insert into realtime.messages(topic, extension, payload)
    values (
      realtime.topic(),
      'broadcast',
      jsonb_build_object(
        'event','typing',
        'payload',jsonb_build_object(
          'user_id','00000000-0000-4000-8000-000000000002',
          'is_typing',true
        )
      )
    );
    raise exception 'A member unexpectedly spoofed the other member typing state';
  exception when insufficient_privilege then
    null;
  end;

  if public.can_use_match_typing_channel(
    '00000000-0000-4000-8000-000000000001',
    '00000000-0000-4000-8000-000000000003'
  ) then
    raise exception 'A blocked pair unexpectedly passed typing-channel authorization';
  end if;
end;
$$;
reset role;

select 'server matchmaking eligibility tests passed' as result;
