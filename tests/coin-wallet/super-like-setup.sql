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
