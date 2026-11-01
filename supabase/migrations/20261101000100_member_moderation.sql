-- Account suspension and permanent-ban foundation for The Match.
create table if not exists public.member_moderation (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null check (status in ('suspended','banned')),
  reason text not null check (length(btrim(reason)) between 3 and 1000),
  expires_at timestamptz,
  actioned_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  constraint moderation_expiry_check check (
    (status = 'suspended' and expires_at is not null) or
    (status = 'banned' and expires_at is null)
  )
);

create table if not exists public.member_moderation_audit (
  id bigint generated always as identity primary key,
  user_id uuid not null,
  action text not null check (action in ('suspended','banned','restored')),
  reason text not null,
  expires_at timestamptz,
  actioned_by uuid not null,
  created_at timestamptz not null default now()
);

alter table public.member_moderation enable row level security;
alter table public.member_moderation_audit enable row level security;
revoke all on public.member_moderation from anon, authenticated;
revoke all on public.member_moderation_audit from anon, authenticated;
grant select on public.member_moderation to authenticated;
grant select on public.member_moderation_audit to authenticated;

drop policy if exists "Admins can read member moderation" on public.member_moderation;
create policy "Admins can read member moderation"
on public.member_moderation for select to authenticated
using ((select public.is_match_admin()));

drop policy if exists "Admins can read moderation audit" on public.member_moderation_audit;
create policy "Admins can read moderation audit"
on public.member_moderation_audit for select to authenticated
using ((select public.is_match_admin()));

create or replace function public.admin_set_member_moderation(
  p_user_id uuid,
  p_action text,
  p_reason text default null,
  p_expires_at timestamptz default null
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_admin uuid := auth.uid();
begin
  if v_admin is null or not public.is_match_admin() then
    raise exception 'Admin access denied';
  end if;
  if p_user_id is null or p_user_id = v_admin then
    raise exception 'You cannot moderate your own account';
  end if;
  if exists (select 1 from public.app_admins where user_id = p_user_id) then
    raise exception 'Administrator accounts cannot be moderated here';
  end if;

  if p_action = 'restored' then
    delete from public.member_moderation where user_id = p_user_id;
    insert into public.member_moderation_audit(user_id, action, reason, actioned_by)
    values (p_user_id, 'restored', coalesce(nullif(btrim(p_reason), ''), 'Account restored by administrator'), v_admin);
  elsif p_action = 'suspended' then
    if p_expires_at is null or p_expires_at <= now() or p_expires_at > now() + interval '30 days' then
      raise exception 'Suspension must expire within the next 30 days';
    end if;
    if length(btrim(coalesce(p_reason,''))) < 3 or length(p_reason) > 1000 then
      raise exception 'A reason between 3 and 1000 characters is required';
    end if;
    insert into public.member_moderation(user_id,status,reason,expires_at,actioned_by,updated_at)
    values(p_user_id,'suspended',btrim(p_reason),p_expires_at,v_admin,now())
    on conflict(user_id) do update set status='suspended',reason=excluded.reason,expires_at=excluded.expires_at,actioned_by=v_admin,updated_at=now();
    insert into public.member_moderation_audit(user_id,action,reason,expires_at,actioned_by)
    values(p_user_id,'suspended',btrim(p_reason),p_expires_at,v_admin);
  elsif p_action = 'banned' then
    if length(btrim(coalesce(p_reason,''))) < 3 or length(p_reason) > 1000 then
      raise exception 'A reason between 3 and 1000 characters is required';
    end if;
    insert into public.member_moderation(user_id,status,reason,expires_at,actioned_by,updated_at)
    values(p_user_id,'banned',btrim(p_reason),null,v_admin,now())
    on conflict(user_id) do update set status='banned',reason=excluded.reason,expires_at=null,actioned_by=v_admin,updated_at=now();
    insert into public.member_moderation_audit(user_id,action,reason,actioned_by)
    values(p_user_id,'banned',btrim(p_reason),v_admin);
  else
    raise exception 'Unsupported moderation action';
  end if;
end;
$$;
revoke all on function public.admin_set_member_moderation(uuid,text,text,timestamptz) from public, anon;
grant execute on function public.admin_set_member_moderation(uuid,text,text,timestamptz) to authenticated;

create or replace function public.can_interact_with_member(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = 'public', 'pg_temp'
as $$
  select auth.uid() is not null
    and target_user_id is not null
    and target_user_id <> auth.uid()
    and not exists (
      select 1 from public.member_blocks mb
      where (mb.blocker_id = auth.uid() and mb.blocked_id = target_user_id)
         or (mb.blocker_id = target_user_id and mb.blocked_id = auth.uid())
    )
    and not exists (
      select 1 from public.member_moderation mm
      where mm.user_id in (auth.uid(), target_user_id)
        and (mm.status = 'banned' or (mm.status = 'suspended' and mm.expires_at > now()))
    );
$$;
