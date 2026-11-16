\set ON_ERROR_STOP on

insert into public.profiles
  (id, display_name, gender_identity, interested_in, bio, city, age, is_verified, sexual_roles, verification_level)
values
  ('00000000-0000-4000-8000-000000000001', 'Viewer', 'Man', 'Men', 'A complete viewer profile', 'Lagos', 30, false, array['Bottom'], 'none'),
  ('00000000-0000-4000-8000-000000000002', 'Candidate', 'Man', 'Men', 'A complete candidate profile', 'Lagos', 27, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000003', 'Blocked', 'Man', 'Men', 'A complete candidate profile', 'Lagos', 27, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000004', 'Suspended', 'Man', 'Men', 'A complete candidate profile', 'Lagos', 27, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000005', 'Banned', 'Man', 'Men', 'A complete candidate profile', 'Lagos', 27, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000006', 'Incomplete', 'Man', 'Men', '', 'Lagos', 27, false, array['Top'], 'none'),
  ('00000000-0000-4000-8000-000000000007', 'Verified', 'Woman', 'Men', 'A complete verified profile', 'Lagos', 28, true, array['Bottom'], 'basic');

insert into public.profile_photos (user_id, storage_path)
select ids.user_id, ids.user_id::text || '-' || photo_no::text
from (values
  ('00000000-0000-4000-8000-000000000001'::uuid),
  ('00000000-0000-4000-8000-000000000002'::uuid),
  ('00000000-0000-4000-8000-000000000003'::uuid),
  ('00000000-0000-4000-8000-000000000004'::uuid),
  ('00000000-0000-4000-8000-000000000005'::uuid),
  ('00000000-0000-4000-8000-000000000006'::uuid),
  ('00000000-0000-4000-8000-000000000007'::uuid)
) ids(user_id)
cross join generate_series(1,2) photo_no;

insert into public.member_blocks values
  ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000003');
insert into public.member_moderation values
  ('00000000-0000-4000-8000-000000000004','suspended',now()+interval '1 day'),
  ('00000000-0000-4000-8000-000000000005','banned',null);
insert into public.premium_memberships values
  ('00000000-0000-4000-8000-000000000001',now()+interval '30 days');

-- Keep the synthetic JWT claim at session scope across separate SQL commands.
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);

do $$
declare
  found_ids uuid[];
begin
  select array_agg(user_id order by user_id)
    into found_ids
  from public.matchmaking_eligible_candidate_ids();

  if found_ids is distinct from array[
    '00000000-0000-4000-8000-000000000002'::uuid,
    '00000000-0000-4000-8000-000000000007'::uuid
  ] then
    raise exception 'Expected only complete, active, unblocked candidates; got %', found_ids;
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
end;
$$;

-- Use a separate SQL command so the moderation assertion sees a fresh statement snapshot.
update public.member_moderation
set status = 'suspended', expires_at = now()+interval '1 day'
where user_id = '00000000-0000-4000-8000-000000000001';

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
    'public.matchmaking_eligible_candidate_ids(double precision,integer,integer,text,text,text[],boolean,integer)',
    'EXECUTE'
  ) then
    raise exception 'Anonymous role must not execute the eligibility function';
  end if;
  if not has_function_privilege(
    'authenticated',
    'public.matchmaking_eligible_candidate_ids(double precision,integer,integer,text,text,text[],boolean,integer)',
    'EXECUTE'
  ) then
    raise exception 'Authenticated role must be able to execute the eligibility function';
  end if;
end;
$$;

select 'server matchmaking eligibility tests passed' as result;
