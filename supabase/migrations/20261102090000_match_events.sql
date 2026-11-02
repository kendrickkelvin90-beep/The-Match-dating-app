-- The Match Events: verified organisers and paid promotion approval workflow.
create table if not exists public.match_events (
  id uuid primary key default gen_random_uuid(),
  organiser_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 5 and 100),
  description text not null check (char_length(trim(description)) between 20 and 2000),
  category text not null check (category in ('social','dating','nightlife','community','online','other')),
  venue text not null check (char_length(trim(venue)) between 2 and 160),
  city text not null check (char_length(trim(city)) between 2 and 100),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  ticket_price_ngn integer not null default 0 check (ticket_price_ngn >= 0),
  promotion_fee_ngn integer not null default 7000 check (promotion_fee_ngn >= 0),
  payment_sender_name text not null check (char_length(trim(payment_sender_name)) between 2 and 120),
  payment_reference text not null check (char_length(trim(payment_reference)) between 4 and 120),
  payment_status text not null default 'pending' check (payment_status in ('pending','approved','rejected')),
  status text not null default 'pending_review' check (status in ('pending_review','published','rejected','cancelled')),
  admin_note text check (admin_note is null or char_length(admin_note) <= 500),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint match_events_valid_dates check (ends_at > starts_at)
);
create index if not exists match_events_public_start_idx on public.match_events (starts_at) where status = 'published';
create index if not exists match_events_organiser_idx on public.match_events (organiser_id, created_at desc);
alter table public.match_events enable row level security;
grant select, insert, update on public.match_events to authenticated;
drop policy if exists "Published events and own submissions are visible" on public.match_events;
create policy "Published events and own submissions are visible"
on public.match_events for select to authenticated
using (status = 'published' or organiser_id = (select auth.uid()) or (select public.is_match_admin()));
drop policy if exists "Verified members can submit paid event listings" on public.match_events;
create policy "Verified members can submit paid event listings"
on public.match_events for insert to authenticated
with check (
  organiser_id = (select auth.uid())
  and exists (select 1 from public.profiles p where p.id = (select auth.uid()) and p.is_verified = true)
  and payment_status = 'pending'
  and status = 'pending_review'
  and promotion_fee_ngn = 7000
  and reviewed_by is null and reviewed_at is null
  and admin_note is null
);
drop policy if exists "Organisers can edit only their unreviewed event details" on public.match_events;
create policy "Organisers can edit only their unreviewed event details"
on public.match_events for update to authenticated
using (organiser_id = (select auth.uid()) and status = 'pending_review' and payment_status = 'pending')
with check (
  organiser_id = (select auth.uid())
  and status = 'pending_review' and payment_status = 'pending'
  and promotion_fee_ngn = 7000
  and reviewed_by is null and reviewed_at is null and admin_note is null
);
drop policy if exists "Admins manage event approvals" on public.match_events;
create policy "Admins manage event approvals"
on public.match_events for update to authenticated
using ((select public.is_match_admin()))
with check ((select public.is_match_admin()));
