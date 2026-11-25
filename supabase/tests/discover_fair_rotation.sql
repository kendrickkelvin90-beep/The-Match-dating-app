\set ON_ERROR_STOP on

-- Expand the eligible pool beyond the 100-ID cap. The old UUID sort always
-- selected the same lowest IDs; the six-hour viewer-specific rotation must
-- draw from the whole pool instead.
insert into public.profiles (
  id, display_name, gender_identity, interested_in, bio, city, age,
  is_verified, sexual_roles, verification_level
)
select
  ('20000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  'Rotation candidate ' || n,
  'Man',
  'All genders',
  'A complete Discover rotation test profile',
  'Lagos',
  25,
  false,
  array['Top']::text[],
  'none'
from generate_series(1,120) n
on conflict (id) do nothing;

insert into public.member_onboarding(user_id, answers)
select
  ('20000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid,
  '{"sexual_orientation":"Bisexual","relationship_goal":"A relationship"}'::jsonb
from generate_series(1,120) n
on conflict (user_id) do update set answers = excluded.answers;

insert into public.profile_photos(user_id, storage_path, position)
select
  candidate_id,
  candidate_id::text || '-rotation-' || photo_no::text,
  photo_no - 1
from (
  select ('20000000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid as candidate_id
  from generate_series(1,120) n
) candidates
cross join generate_series(1,2) photo_no
on conflict (storage_path) do nothing;

delete from public.member_moderation
where user_id = '00000000-0000-4000-8000-000000000001';

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);

do $fair_rotation$
declare
  selected_count integer;
  selected_from_later_ids integer;
begin
  select count(*),
         count(*) filter (
           where user_id > '20000000-0000-4000-8000-000000000100'::uuid
         )
    into selected_count, selected_from_later_ids
  from public.matchmaking_eligible_candidate_ids();

  if selected_count <> 100 then
    raise exception 'Discover should still respect the 100-profile response cap; got %', selected_count;
  end if;

  if selected_from_later_ids = 0 then
    raise exception 'Discover candidate selection is still biased toward the first UUIDs';
  end if;
end;
$fair_rotation$;

select 'fair Discover candidate rotation tests passed' as result;
