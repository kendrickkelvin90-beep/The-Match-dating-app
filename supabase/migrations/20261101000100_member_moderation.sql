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

-- A member is active unless a current suspension or ban is recorded.
-- This helper is deliberately separate from can_interact_with_member(), because
-- members must be able to check their own account state without comparing to themselves.
create or replace function public.is_member_account_active(target_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select target_user_id is not null
    and not exists (
      select 1
      from public.member_moderation mm
      where mm.user_id = target_user_id
        and (
          mm.status = 'banned'
          or (mm.status = 'suspended' and mm.expires_at > now())
        )
    );
$$;
revoke all on function public.is_member_account_active(uuid) from public, anon;
grant execute on function public.is_member_account_active(uuid) to authenticated;

-- Keep the original two-way block check and additionally deny interactions
-- whenever either account is currently suspended or banned.
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
    and public.is_member_account_active(auth.uid())
    and public.is_member_account_active(target_user_id)
    and not exists (
      select 1
      from public.member_blocks mb
      where (mb.blocker_id = auth.uid() and mb.blocked_id = target_user_id)
         or (mb.blocker_id = target_user_id and mb.blocked_id = auth.uid())
    );
$$;

-- Restrictive policies are ANDed with existing policies. They add moderation
-- enforcement without replacing the app's existing ownership and matching rules.
drop policy if exists "Moderation restricts profile reads" on public.profiles;
create policy "Moderation restricts profile reads"
on public.profiles as restrictive for select to authenticated
using (
  public.is_match_admin()
  or id = auth.uid()
  or public.can_interact_with_member(id)
);

drop policy if exists "Moderation restricts profile inserts" on public.profiles;
create policy "Moderation restricts profile inserts"
on public.profiles as restrictive for insert to authenticated
with check (id = auth.uid() and public.is_member_account_active(auth.uid()));

drop policy if exists "Moderation restricts profile updates" on public.profiles;
create policy "Moderation restricts profile updates"
on public.profiles as restrictive for update to authenticated
using (public.is_member_account_active(auth.uid()))
with check (public.is_member_account_active(auth.uid()));

drop policy if exists "Moderation restricts likes" on public.likes;
create policy "Moderation restricts likes"
on public.likes as restrictive for insert to authenticated
with check (
  liker_id = auth.uid()
  and public.is_member_account_active(auth.uid())
  and public.can_interact_with_member(liked_id)
);

drop policy if exists "Moderation restricts story creation" on public.stories;
create policy "Moderation restricts story creation"
on public.stories as restrictive for insert to authenticated
with check (user_id = auth.uid() and public.is_member_account_active(auth.uid()));

drop policy if exists "Moderation restricts story views" on public.story_views;
create policy "Moderation restricts story views"
on public.story_views as restrictive for insert to authenticated
with check (
  viewer_id = auth.uid()
  and public.is_member_account_active(auth.uid())
  and exists (
    select 1 from public.stories s
    where s.id = story_views.story_id
      and s.user_id <> auth.uid()
      and s.expires_at > now()
      and public.can_interact_with_member(s.user_id)
  )
);

drop policy if exists "Moderation restricts profile passes" on public.profile_passes;
create policy "Moderation restricts profile passes"
on public.profile_passes as restrictive for insert to authenticated
with check (
  passer_id = auth.uid()
  and public.is_member_account_active(auth.uid())
  and public.can_interact_with_member(passed_id)
);

drop policy if exists "Moderation restricts block creation" on public.member_blocks;
create policy "Moderation restricts block creation"
on public.member_blocks as restrictive for insert to authenticated
with check (
  blocker_id = auth.uid()
  and public.is_member_account_active(auth.uid())
  and public.is_member_account_active(blocked_id)
);

drop policy if exists "Moderation restricts report submission" on public.member_reports;
create policy "Moderation restricts report submission"
on public.member_reports as restrictive for insert to authenticated
with check (reporter_id = auth.uid() and public.is_member_account_active(auth.uid()));

drop policy if exists "Moderation restricts verification requests" on public.verification_requests;
create policy "Moderation restricts verification requests"
on public.verification_requests as restrictive for insert to authenticated
with check (user_id = auth.uid() and public.is_member_account_active(auth.uid()));

drop policy if exists "Moderation restricts premium payment requests" on public.premium_payment_requests;
create policy "Moderation restricts premium payment requests"
on public.premium_payment_requests as restrictive for insert to authenticated
with check (user_id = auth.uid() and public.is_member_account_active(auth.uid()));

drop policy if exists "Moderation restricts onboarding changes" on public.member_onboarding;
create policy "Moderation restricts onboarding changes"
on public.member_onboarding as restrictive for all to authenticated
using (public.is_member_account_active(auth.uid()))
with check (public.is_member_account_active(auth.uid()));

drop policy if exists "Moderation restricts private detail changes" on public.member_private_details;
create policy "Moderation restricts private detail changes"
on public.member_private_details as restrictive for all to authenticated
using (public.is_member_account_active(auth.uid()))
with check (public.is_member_account_active(auth.uid()));

drop policy if exists "Moderation restricts profile photo inserts" on public.profile_photos;
create policy "Moderation restricts profile photo inserts"
on public.profile_photos as restrictive for insert to authenticated
with check (user_id = auth.uid() and public.is_member_account_active(auth.uid()));

drop policy if exists "Moderation restricts profile photo updates" on public.profile_photos;
create policy "Moderation restricts profile photo updates"
on public.profile_photos as restrictive for update to authenticated
using (user_id = auth.uid() and public.is_member_account_active(auth.uid()))
with check (user_id = auth.uid() and public.is_member_account_active(auth.uid()));

drop policy if exists "Moderation restricts profile photo deletes" on public.profile_photos;
create policy "Moderation restricts profile photo deletes"
on public.profile_photos as restrictive for delete to authenticated
using (user_id = auth.uid() and public.is_member_account_active(auth.uid()));

-- Stop suspended/banned members from uploading directly to Supabase Storage.
-- Existing bucket ownership/path rules remain in place and are ANDed with these.
drop policy if exists "Moderation restricts profile photo uploads" on storage.objects;
create policy "Moderation restricts profile photo uploads"
on storage.objects as restrictive for insert to authenticated
with check (
  bucket_id <> 'profile-photos'
  or public.is_member_account_active(auth.uid())
);

drop policy if exists "Moderation restricts story media uploads" on storage.objects;
create policy "Moderation restricts story media uploads"
on storage.objects as restrictive for insert to authenticated
with check (
  bucket_id <> 'story-media'
  or public.is_member_account_active(auth.uid())
);

drop policy if exists "Moderation restricts verification selfie uploads" on storage.objects;
create policy "Moderation restricts verification selfie uploads"
on storage.objects as restrictive for insert to authenticated
with check (
  bucket_id <> 'verification-selfies'
  or public.is_member_account_active(auth.uid())
);

drop policy if exists "Moderation restricts chat media uploads" on storage.objects;
create policy "Moderation restricts chat media uploads"
on storage.objects as restrictive for insert to authenticated
with check (
  bucket_id <> 'chat-media'
  or public.is_member_account_active(auth.uid())
);
