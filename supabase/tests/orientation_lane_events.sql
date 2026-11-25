\set ON_ERROR_STOP on

-- User 10 has a disclosed LGBTQ+ orientation. Remove the legacy lane key so
-- this specifically verifies that an orientation-only account can organise.
-- Event visibility and notifications must use the same lane as Discover.

update public.member_onboarding
set answers = answers - 'dating_community'
where user_id = '00000000-0000-4000-8000-000000000010';

insert into auth.users(id)
values
  ('00000000-0000-4000-8000-000000000001'),
  ('00000000-0000-4000-8000-000000000002'),
  ('00000000-0000-4000-8000-000000000010')
on conflict (id) do nothing;

update public.profiles
set is_verified = true
where id = '00000000-0000-4000-8000-000000000010';

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000010',false);
set role authenticated;

insert into public.match_events (
  organiser_id, title, description, category, venue, city,
  starts_at, ends_at, ticket_price_ngn, promotion_fee_ngn,
  payment_sender_name, payment_reference
)
values (
  auth.uid(),
  'Orientation lane test event',
  'A test event used to verify orientation-derived event audience separation.',
  'community',
  'Private test venue',
  'Lagos',
  now() + interval '2 days',
  now() + interval '2 days 3 hours',
  0,
  7000,
  'Test organiser',
  'TEST-ORIENTATION-LANE-001'
);

reset role;

do $event_created$
declare
  event_lane text;
begin
  select community into event_lane
  from public.match_events
  where organiser_id = '00000000-0000-4000-8000-000000000010'
    and title = 'Orientation lane test event';

  if event_lane is distinct from 'lgbtq' then
    raise exception 'Orientation-only LGBTQ+ organiser should create an LGBTQ+ event; got %', event_lane;
  end if;
end;
$event_created$;

-- Simulate the admin approval path; the event's audience remains immutable.
select set_config('test.is_admin','true',false);
update public.match_events
set status = 'published'
where organiser_id = '00000000-0000-4000-8000-000000000010'
  and title = 'Orientation lane test event';
select set_config('test.is_admin','false',false);

do $event_notifications$
begin
  if not exists (
    select 1 from public.notifications
    where user_id = '00000000-0000-4000-8000-000000000001'
      and type = 'event_published'
      and action_url like 'event:%'
  ) then
    raise exception 'Published LGBTQ+ event should notify a member in the same orientation-derived lane';
  end if;

  if exists (
    select 1 from public.notifications
    where user_id = '00000000-0000-4000-8000-000000000002'
      and type = 'event_published'
      and action_url like 'event:%'
  ) then
    raise exception 'Published LGBTQ+ event must not notify a straight-lane member';
  end if;
end;
$event_notifications$;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
set role authenticated;
do $same_lane_visibility$
begin
  if not exists (
    select 1 from public.match_events
    where title = 'Orientation lane test event'
  ) then
    raise exception 'A same-lane member should see the published event';
  end if;
end;
$same_lane_visibility$;
reset role;

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',false);
set role authenticated;
do $cross_lane_visibility$
begin
  if exists (
    select 1 from public.match_events
    where title = 'Orientation lane test event'
  ) then
    raise exception 'A straight-lane member must not see an LGBTQ+ event';
  end if;
end;
$cross_lane_visibility$;
reset role;

do $legacy_policy$
begin
  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'match_events'
      and policyname = 'Published events and own submissions are visible'
  ) then
    raise exception 'The old permissive all-published-events policy must be removed';
  end if;
end;
$legacy_policy$;

select 'orientation-derived event lane tests passed' as result;
