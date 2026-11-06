-- Store each member's conversation favorites securely and sync them across devices.
create table if not exists public.conversation_favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  conversation_user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint conversation_favorites_pkey primary key (user_id, conversation_user_id),
  constraint conversation_favorites_not_self check (user_id <> conversation_user_id)
);

alter table public.conversation_favorites enable row level security;

create policy "Members can read their own conversation favorites"
  on public.conversation_favorites for select to authenticated
  using ((select auth.uid()) = user_id);

create policy "Members can add their own conversation favorites"
  on public.conversation_favorites for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Members can remove their own conversation favorites"
  on public.conversation_favorites for delete to authenticated
  using ((select auth.uid()) = user_id);

grant select, insert, delete on public.conversation_favorites to authenticated;
revoke all on public.conversation_favorites from anon;
