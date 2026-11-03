-- Premium discovery benefits: swipe rewind, profile boosts, and membership badges.
create table if not exists public.match_swipe_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  target_user_id uuid not null references auth.users(id) on delete cascade,
  action text not null check (action in ('like','pass')),
  created_at timestamptz not null default now()
);
create index if not exists match_swipe_history_user_created_idx
  on public.match_swipe_history(user_id, created_at desc);

alter table public.match_swipe_history enable row level security;
revoke all on public.match_swipe_history from anon, authenticated;

create or replace function public.record_match_swipe_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_target uuid;
  v_action text;
begin
  if tg_table_name = 'likes' then
    v_user := new.liker_id;
    v_target := new.liked_id;
    v_action := 'like';
  else
    v_user := new.passer_id;
    v_target := new.passed_id;
    v_action := 'pass';
  end if;

  if v_user is not null and v_target is not null and auth.uid() = v_user then
    insert into public.match_swipe_history(user_id,target_user_id,action,created_at)
    values(v_user,v_target,v_action,coalesce(new.created_at,now()));
  end if;
  return new;
end;
$$;

drop trigger if exists record_like_swipe_history on public.likes;
create trigger record_like_swipe_history
after insert on public.likes
for each row execute function public.record_match_swipe_history();

drop trigger if exists record_pass_swipe_history on public.profile_passes;
create trigger record_pass_swipe_history
after insert or update of created_at on public.profile_passes
for each row execute function public.record_match_swipe_history();

create or replace function public.rewind_my_last_swipe()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_swipe public.match_swipe_history%rowtype;
  v_is_premium boolean;
begin
  if v_user is null then
    raise exception 'Authentication required.';
  end if;

  select exists (
    select 1 from public.premium_memberships pm
    where pm.user_id = v_user and pm.premium_until > now()
  ) into v_is_premium;

  if not v_is_premium then
    raise exception 'PREMIUM_REQUIRED: Rewind is a Premium feature.';
  end if;

  select * into v_swipe
  from public.match_swipe_history
  where user_id = v_user
  order by created_at desc, id desc
  limit 1
  for update;

  if v_swipe.id is null then
    raise exception 'NO_SWIPE_TO_REWIND: There is no previous swipe to undo.';
  end if;

  if v_swipe.created_at < now() - interval '24 hours' then
    raise exception 'SWIPE_TOO_OLD: The previous swipe is too old to rewind.';
  end if;

  if v_swipe.action = 'like' then
    if exists (
      select 1 from public.likes l
      where l.liker_id = v_swipe.target_user_id
        and l.liked_id = v_user
    ) then
      raise exception 'MATCH_ALREADY_CREATED: A mutual match cannot be rewound.';
    end if;
    delete from public.likes
    where liker_id = v_user and liked_id = v_swipe.target_user_id;
  else
    delete from public.profile_passes
    where passer_id = v_user and passed_id = v_swipe.target_user_id;
  end if;

  delete from public.match_swipe_history where id = v_swipe.id;
  return jsonb_build_object('success',true,'target_user_id',v_swipe.target_user_id,'action',v_swipe.action);
end;
$$;

revoke all on function public.rewind_my_last_swipe() from public, anon;
grant execute on function public.rewind_my_last_swipe() to authenticated;

create table if not exists public.profile_boosts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  starts_at timestamptz not null default now(),
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  constraint profile_boosts_valid_window check (ends_at > starts_at)
);
create index if not exists profile_boosts_active_idx
  on public.profile_boosts(ends_at desc, starts_at desc);
alter table public.profile_boosts enable row level security;
revoke all on public.profile_boosts from anon, authenticated;

create or replace function public.activate_my_profile_boost()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_last timestamptz;
  v_end timestamptz;
begin
  if v_user is null then raise exception 'Authentication required.'; end if;
  if not exists (
    select 1 from public.premium_memberships pm
    where pm.user_id = v_user and pm.premium_until > now()
  ) then
    raise exception 'PREMIUM_REQUIRED: Profile Boost is a Premium feature.';
  end if;

  select max(created_at) into v_last
  from public.profile_boosts where user_id = v_user;

  if v_last is not null and v_last > now() - interval '24 hours' then
    raise exception 'BOOST_COOLDOWN: You can activate one profile boost every 24 hours.';
  end if;

  v_end := now() + interval '30 minutes';
  insert into public.profile_boosts(user_id,starts_at,ends_at)
  values(v_user,now(),v_end);

  return jsonb_build_object('success',true,'ends_at',v_end);
end;
$$;

revoke all on function public.activate_my_profile_boost() from public, anon;
grant execute on function public.activate_my_profile_boost() to authenticated;

create or replace function public.get_active_discover_boost_ids()
returns setof uuid
language sql
stable
security definer
set search_path = ''
as $$
  select distinct b.user_id
  from public.profile_boosts b
  where b.starts_at <= now() and b.ends_at > now();
$$;
revoke all on function public.get_active_discover_boost_ids() from public, anon;
grant execute on function public.get_active_discover_boost_ids() to authenticated;

create or replace function public.get_active_premium_member_ids(p_user_ids uuid[])
returns table(user_id uuid)
language sql
stable
security definer
set search_path = ''
as $$
  select pm.user_id
  from public.premium_memberships pm
  where pm.user_id = any(coalesce(p_user_ids, array[]::uuid[]))
    and pm.premium_until > now();
$$;
revoke all on function public.get_active_premium_member_ids(uuid[]) from public, anon;
grant execute on function public.get_active_premium_member_ids(uuid[]) to authenticated;
