-- Privacy-first event participation and reporting.
-- Members can read/change only their own response. Organisers never receive attendee lists.
create table if not exists public.match_event_responses (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.match_events(id) on delete cascade,
  member_id uuid not null references auth.users(id) on delete cascade,
  response text not null check (response in ('interested','going')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, member_id)
);
create index if not exists match_event_responses_member_idx
  on public.match_event_responses (member_id, updated_at desc);
alter table public.match_event_responses enable row level security;
grant select, insert, update, delete on public.match_event_responses to authenticated;
drop policy if exists "Members can read only their own event response" on public.match_event_responses;
create policy "Members can read only their own event response"
on public.match_event_responses for select to authenticated
using (member_id = (select auth.uid()));
drop policy if exists "Members can respond privately to published events" on public.match_event_responses;
create policy "Members can respond privately to published events"
on public.match_event_responses for insert to authenticated
with check (
  member_id = (select auth.uid())
  and exists (
    select 1 from public.match_events e
    where e.id = event_id and e.status = 'published'
  )
);
drop policy if exists "Members can update only their own event response" on public.match_event_responses;
create policy "Members can update only their own event response"
on public.match_event_responses for update to authenticated
using (member_id = (select auth.uid()))
with check (
  member_id = (select auth.uid())
  and exists (
    select 1 from public.match_events e
    where e.id = event_id and e.status = 'published'
  )
);
drop policy if exists "Members can remove only their own event response" on public.match_event_responses;
create policy "Members can remove only their own event response"
on public.match_event_responses for delete to authenticated
using (member_id = (select auth.uid()));

-- Reports are private to the reporter and authorised admins; never visible to organisers.
create table if not exists public.match_event_reports (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.match_events(id) on delete cascade,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (reason in ('fake_event','scam_or_payment','harassment','unsafe_location','misleading_information','other')),
  details text check (details is null or char_length(details) <= 1000),
  status text not null default 'open' check (status in ('open','reviewing','resolved','dismissed')),
  admin_note text check (admin_note is null or char_length(admin_note) <= 500),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  unique (event_id, reporter_id)
);
create index if not exists match_event_reports_status_idx
  on public.match_event_reports (status, created_at desc);
alter table public.match_event_reports enable row level security;
grant select, insert, update on public.match_event_reports to authenticated;
drop policy if exists "Reporters and admins can read event reports" on public.match_event_reports;
create policy "Reporters and admins can read event reports"
on public.match_event_reports for select to authenticated
using (reporter_id = (select auth.uid()) or (select public.is_match_admin()));
drop policy if exists "Members can report published events" on public.match_event_reports;
create policy "Members can report published events"
on public.match_event_reports for insert to authenticated
with check (
  reporter_id = (select auth.uid())
  and status = 'open'
  and admin_note is null
  and reviewed_by is null
  and reviewed_at is null
  and exists (
    select 1 from public.match_events e
    where e.id = event_id and e.status = 'published'
  )
);
drop policy if exists "Admins can update event reports" on public.match_event_reports;
create policy "Admins can update event reports"
on public.match_event_reports for update to authenticated
using ((select public.is_match_admin()))
with check ((select public.is_match_admin()));
