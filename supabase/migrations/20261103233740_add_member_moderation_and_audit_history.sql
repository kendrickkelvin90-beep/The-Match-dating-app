create table if not exists public.member_moderation (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null check (status in ('suspended','banned','restored')),
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  expires_at timestamptz,
  updated_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint member_moderation_expiry_check check (
    (status = 'suspended' and expires_at is not null) or
    (status in ('banned','restored') and expires_at is null)
  )
);

create table if not exists public.member_moderation_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  action text not null check (action in ('suspended','banned','restored')),
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  expires_at timestamptz,
  actor_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists member_moderation_history_user_created_idx
  on public.member_moderation_history(user_id, created_at desc);

alter table public.member_moderation enable row level security;
alter table public.member_moderation_history enable row level security;

drop policy if exists "Members can read their own moderation status" on public.member_moderation;
create policy "Members can read their own moderation status"
  on public.member_moderation for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Admins can review all moderation statuses" on public.member_moderation;
create policy "Admins can review all moderation statuses"
  on public.member_moderation for select to authenticated
  using (public.is_match_admin());

drop policy if exists "Admins can review moderation history" on public.member_moderation_history;
create policy "Admins can review moderation history"
  on public.member_moderation_history for select to authenticated
  using (public.is_match_admin());

grant select on public.member_moderation to authenticated;
grant select on public.member_moderation_history to authenticated;
revoke all on public.member_moderation from anon;
revoke all on public.member_moderation_history from anon;

create or replace function public.record_member_moderation(
  p_user_id uuid,
  p_action text,
  p_reason text,
  p_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := (select auth.uid());
begin
  if actor is null or not public.is_match_admin() then
    raise exception 'Admin access denied.' using errcode = '42501';
  end if;
  if p_user_id is null or p_user_id = actor then
    raise exception 'You cannot moderate your own account.';
  end if;
  if exists (select 1 from public.app_admins where user_id = p_user_id) then
    raise exception 'Administrator accounts cannot be moderated here.';
  end if;
  if p_action not in ('suspended','banned','restored') then
    raise exception 'Invalid moderation action.';
  end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 or char_length(btrim(p_reason)) > 500 then
    raise exception 'Enter a moderation reason between 3 and 500 characters.';
  end if;
  if p_action = 'suspended' and (
    p_expires_at is null or p_expires_at <= now()
    or p_expires_at > now() + interval '30 days'
  ) then
    raise exception 'A suspension must expire within the next 30 days.';
  end if;
  if p_action in ('banned','restored') and p_expires_at is not null then
    raise exception 'This moderation action cannot have an expiry date.';
  end if;

  insert into public.member_moderation
    (user_id, status, reason, expires_at, updated_by, created_at, updated_at)
  values
    (p_user_id, p_action, btrim(p_reason), p_expires_at, actor, now(), now())
  on conflict (user_id) do update set
    status = excluded.status,
    reason = excluded.reason,
    expires_at = excluded.expires_at,
    updated_by = excluded.updated_by,
    updated_at = now();

  insert into public.member_moderation_history
    (user_id, action, reason, expires_at, actor_id)
  values
    (p_user_id, p_action, btrim(p_reason), p_expires_at, actor);

  return jsonb_build_object('success', true, 'user_id', p_user_id, 'action', p_action);
end;
$function$;

revoke all on function public.record_member_moderation(uuid,text,text,timestamptz) from public, anon;
grant execute on function public.record_member_moderation(uuid,text,text,timestamptz) to authenticated;
