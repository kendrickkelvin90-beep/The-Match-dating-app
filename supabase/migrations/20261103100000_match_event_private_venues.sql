-- Keep exact event venues out of the publicly readable event row.
create table if not exists public.match_event_private_details (
  event_id uuid primary key references public.match_events(id) on delete cascade,
  venue text not null check (char_length(trim(venue)) between 2 and 500),
  updated_at timestamptz not null default now()
);
alter table public.match_event_private_details enable row level security;
grant select, insert, update on public.match_event_private_details to authenticated;
-- Move existing venue values into the protected table before replacing the public value.
insert into public.match_event_private_details (event_id, venue)
select id, venue from public.match_events
on conflict (event_id) do nothing;
update public.match_events
set venue = 'Venue details shared privately with members who choose Going'
where venue <> 'Venue details shared privately with members who choose Going';
drop policy if exists "Going members and organisers can read private event venue" on public.match_event_private_details;
create policy "Going members and organisers can read private event venue"
on public.match_event_private_details for select to authenticated
using (
  exists (select 1 from public.match_events e where e.id = event_id and e.organiser_id = (select auth.uid()))
  or (select public.is_match_admin())
  or exists (
    select 1 from public.match_event_responses r
    where r.event_id = event_id and r.member_id = (select auth.uid()) and r.response = 'going'
  )
);
drop policy if exists "Organisers can add private venue to own pending event" on public.match_event_private_details;
create policy "Organisers can add private venue to own pending event"
on public.match_event_private_details for insert to authenticated
with check (
  exists (select 1 from public.match_events e where e.id = event_id and e.organiser_id = (select auth.uid()) and e.status = 'pending_review')
);
drop policy if exists "Organisers can edit private venue on own pending event" on public.match_event_private_details;
create policy "Organisers can edit private venue on own pending event"
on public.match_event_private_details for update to authenticated
using (
  exists (select 1 from public.match_events e where e.id = event_id and e.organiser_id = (select auth.uid()) and e.status = 'pending_review')
)
with check (
  exists (select 1 from public.match_events e where e.id = event_id and e.organiser_id = (select auth.uid()) and e.status = 'pending_review')
);
