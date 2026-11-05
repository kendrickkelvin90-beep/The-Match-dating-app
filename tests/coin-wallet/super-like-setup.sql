-- Minimal existing app tables required to exercise Discover Super Likes.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade
);
create table if not exists public.likes (
  liker_id uuid not null references auth.users(id) on delete cascade,
  liked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(liker_id, liked_id),
  constraint likes_not_self check (liker_id <> liked_id)
);
insert into public.profiles(id)
select id from auth.users
on conflict(id) do nothing;

-- Disposable message/ticket fixture for Profile Boost first-message tests.
-- The profiles table is created by super-like-setup.sql before this file runs.
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);
alter table public.messages enable row level security;
grant select, insert on public.messages to authenticated;
drop policy if exists messages_fixture_select_participants on public.messages;
create policy messages_fixture_select_participants
  on public.messages for select to authenticated
  using (sender_id=(select auth.uid()) or receiver_id=(select auth.uid()));
drop policy if exists messages_fixture_insert_sender on public.messages;
create policy messages_fixture_insert_sender
  on public.messages for insert to authenticated
  with check (sender_id=(select auth.uid()));
