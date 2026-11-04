-- Match Plus / Quarterly / Annual server-side entitlement connections.
-- Staged for isolated testing only. Do not apply to production until reviewed.
create table if not exists public.match_plus_daily_usage (
  user_id uuid not null references auth.users(id) on delete cascade,
  usage_day date not null,
  rewinds_used integer not null default 0 check (rewinds_used >= 0),
  stories_created integer not null default 0 check (stories_created >= 0),
  primary key (user_id, usage_day)
);
alter table public.match_plus_daily_usage enable row level security;
revoke all on public.match_plus_daily_usage from anon, authenticated;

create or replace function public.match_plus_active_tier()
returns text
language sql stable security definer set search_path = ''
as $$
  select case when m.expires_at > now() then m.tier else null end
  from public.match_plus_memberships m
  where m.user_id = (select auth.uid())
$$;
revoke all on function public.match_plus_active_tier() from public, anon;
grant execute on function public.match_plus_active_tier() to authenticated;

create or replace function public.match_has_unlimited_swipes()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists(select 1 from public.premium_memberships pm where pm.user_id=(select auth.uid()) and pm.premium_until>now())
    or exists(select 1 from public.lite_memberships lm where lm.user_id=(select auth.uid()) and lm.lite_until>now())
    or public.match_plus_active_tier() in ('quarterly','annual')
$$;
revoke all on function public.match_has_unlimited_swipes() from public, anon;
grant execute on function public.match_has_unlimited_swipes() to authenticated;

-- The live trigger is attached to enforce_daily_swipe_limit(), not enforce_daily_like_limit().
-- Preserve the existing 20 total daily swipe cap and Premium/Lite unlimited access.
-- Quarterly and Annual also receive unlimited swipes; Match Plus retains the free cap.
create or replace function public.enforce_daily_swipe_limit()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid;
  v_swipes_today integer;
begin
  if tg_table_name = 'likes' then v_user := new.liker_id;
  else v_user := new.passer_id;
  end if;
  if auth.uid() is null or auth.uid() <> v_user then
    raise exception 'You can only swipe as yourself.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text, 0));
  if public.match_has_unlimited_swipes() then return new; end if;
  select count(*)::integer into v_swipes_today
  from public.match_swipe_history h
  where h.user_id = v_user
    and h.created_at >= (date_trunc('day', now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos');
  if v_swipes_today >= 20 then
    raise exception 'DAILY_SWIPE_LIMIT: Free members can make 20 swipes per day. Upgrade to Match Lite or Match Quarterly/Annual for unlimited swipes.';
  end if;
  return new;
end;
$$;

-- Nearby access is granted to all active Match Plus tiers while retaining Premium.
create or replace function public.premium_nearby_profiles_secure(p_max_distance_km double precision default 50)
returns table(id uuid, display_name text, age smallint, gender_identity text, city text, bio text,
  nearby_current_city text, nearby_current_state text, is_verified boolean, verification_level text, distance_km double precision)
language sql stable security definer set search_path = ''
as $$
  select p.id,p.display_name,p.age,p.gender_identity,p.city,p.bio,p.nearby_current_city,p.nearby_current_state,
    p.is_verified,p.verification_level,
    public.calculate_distance_km(my_loc.nearby_latitude,my_loc.nearby_longitude,
      other_loc.nearby_latitude,other_loc.nearby_longitude) as distance_km
  from public.profiles p
  join private.profile_locations other_loc on other_loc.user_id=p.id
  join private.profile_locations my_loc on my_loc.user_id=auth.uid()
  where auth.uid() is not null
    and (
      exists(select 1 from public.premium_memberships pm where pm.user_id=auth.uid() and pm.premium_until>now())
      or public.match_plus_active_tier() in ('plus','quarterly','annual')
    )
    and p.id<>auth.uid() and p.location_sharing is true and other_loc.discovery_sharing is true
    and exists(select 1 from public.profiles viewer where viewer.id=auth.uid() and viewer.location_sharing is true)
    and my_loc.nearby_latitude is not null and my_loc.nearby_longitude is not null
    and my_loc.nearby_updated_at>=now()-interval '7 days'
    and other_loc.nearby_latitude is not null and other_loc.nearby_longitude is not null
    and other_loc.nearby_updated_at>=now()-interval '7 days'
    and public.calculate_distance_km(my_loc.nearby_latitude,my_loc.nearby_longitude,
      other_loc.nearby_latitude,other_loc.nearby_longitude)
      <= greatest(1,least(coalesce(p_max_distance_km,50),50))
    and public.can_interact_with_member(p.id) is true;
$$;
revoke all on function public.premium_nearby_profiles_secure(double precision) from public, anon;
grant execute on function public.premium_nearby_profiles_secure(double precision) to authenticated;

-- Rewind allowances: Plus 3/day, Quarterly 10/day, Annual unlimited; Premium remains unlimited.
-- Validate the swipe before consuming a daily allowance, and serialize per-user requests.
create or replace function public.rewind_my_last_swipe()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_user uuid:=auth.uid();
  v_swipe public.match_swipe_history%rowtype;
  v_tier text;
  v_limit integer;
  v_used integer;
  v_day date:=(now() at time zone 'Africa/Lagos')::date;
begin
  if v_user is null then raise exception 'Authentication required.'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text, 1));
  select * into v_swipe from public.match_swipe_history
    where user_id=v_user order by created_at desc,id desc limit 1 for update;
  if v_swipe.id is null then raise exception 'NO_SWIPE_TO_REWIND: There is no previous swipe to undo.'; end if;
  if v_swipe.created_at<now()-interval '24 hours' then raise exception 'SWIPE_TOO_OLD: The previous swipe is too old to rewind.'; end if;
  if v_swipe.action='like' and exists(
    select 1 from public.likes l where l.liker_id=v_swipe.target_user_id and l.liked_id=v_user
  ) then raise exception 'MATCH_ALREADY_CREATED: A mutual match cannot be rewound.'; end if;

  if exists(select 1 from public.premium_memberships pm where pm.user_id=v_user and pm.premium_until>now()) then
    v_limit:=null;
  else
    v_tier:=public.match_plus_active_tier();
    v_limit:=case v_tier when 'plus' then 3 when 'quarterly' then 10 when 'annual' then null else 0 end;
  end if;
  if v_limit=0 then raise exception 'MEMBERSHIP_REQUIRED: Rewind is included with Match Plus and above or Premium.'; end if;
  if v_limit is not null then
    insert into public.match_plus_daily_usage(user_id,usage_day,rewinds_used)
    values(v_user,v_day,1)
    on conflict(user_id,usage_day) do update
      set rewinds_used=public.match_plus_daily_usage.rewinds_used+1
      where public.match_plus_daily_usage.rewinds_used < v_limit
    returning rewinds_used into v_used;
    if v_used is null then raise exception 'REWIND_DAILY_LIMIT: You have used today’s Rewinds.'; end if;
  end if;

  if v_swipe.action='like' then
    delete from public.likes where liker_id=v_user and liked_id=v_swipe.target_user_id;
  else
    delete from public.profile_passes where passer_id=v_user and passed_id=v_swipe.target_user_id;
  end if;
  delete from public.match_swipe_history where id=v_swipe.id;
  return jsonb_build_object('success',true,'target_user_id',v_swipe.target_user_id,'action',v_swipe.action,
    'rewinds_remaining',case when v_limit is null then null else greatest(0,v_limit-coalesce(v_used,0)) end);
end;
$$;
revoke all on function public.rewind_my_last_swipe() from public, anon;
grant execute on function public.rewind_my_last_swipe() to authenticated;

-- Existing Premium boost stays 30 minutes / 24-hour cooldown.
-- Quarterly receives one boost per 7 days; Annual receives one per 24 hours.
create or replace function public.activate_my_profile_boost()
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare v_user uuid:=auth.uid(); v_last timestamptz; v_end timestamptz; v_tier text; v_cooldown interval;
begin
  if v_user is null then raise exception 'Authentication required.'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text, 2));
  if exists(select 1 from public.premium_memberships pm where pm.user_id=v_user and pm.premium_until>now()) then
    v_cooldown:=interval '24 hours';
  else
    v_tier:=public.match_plus_active_tier();
    v_cooldown:=case v_tier when 'quarterly' then interval '7 days' when 'annual' then interval '24 hours' else null end;
  end if;
  if v_cooldown is null then raise exception 'MEMBERSHIP_REQUIRED: Profile Boost is included with Match Quarterly/Annual or Premium.'; end if;
  select max(created_at) into v_last from public.profile_boosts where user_id=v_user;
  if v_last is not null and v_last>now()-v_cooldown then
    raise exception 'BOOST_COOLDOWN: Your next boost is available after the membership cooldown.';
  end if;
  v_end:=now()+interval '30 minutes';
  insert into public.profile_boosts(user_id,starts_at,ends_at) values(v_user,now(),v_end);
  return jsonb_build_object('success',true,'ends_at',v_end);
end;
$$;
revoke all on function public.activate_my_profile_boost() from public, anon;
grant execute on function public.activate_my_profile_boost() to authenticated;

-- Membership checkout only: Store item spending remains unavailable until fulfillment is built.
create or replace function public.coin_buy_membership(p_tier text,p_idempotency_key text)
returns integer language plpgsql security definer set search_path = ''
as $$
declare v_code text; v_current_tier text; v_current_expiry timestamptz; v_new_rank integer; v_current_rank integer;
begin
  v_code:=case p_tier when 'plus' then 'plus_30d' when 'quarterly' then 'quarterly_90d'
    when 'annual' then 'annual_365d' else null end;
  if v_code is null then raise exception 'Invalid Match membership tier'; end if;
  select tier,expires_at into v_current_tier,v_current_expiry
    from public.match_plus_memberships where user_id=auth.uid() for update;
  v_new_rank:=case p_tier when 'plus' then 1 when 'quarterly' then 2 else 3 end;
  v_current_rank:=case v_current_tier when 'plus' then 1 when 'quarterly' then 2 when 'annual' then 3 else 0 end;
  if v_current_expiry>now() and v_current_rank>v_new_rank then
    raise exception 'Your current Match Plus tier is higher. Wait until it expires or choose an upgrade.';
  end if;
  return public.coin_spend(v_code,1,p_idempotency_key);
end;
$$;
revoke all on function public.coin_buy_membership(text,text) from public, anon;
grant execute on function public.coin_buy_membership(text,text) to authenticated;

comment on table public.match_plus_daily_usage is 'Lagos-day usage counters for Match Plus tier allowances.';


-- Replace the function already attached to enforce_story_upload_limit_trigger.
-- This preserves the existing trigger and its 24-hour free/Lite rule without stacking
-- a second trigger. Per-user advisory locking keeps Plus daily counts atomic.
create or replace function public.enforce_story_upload_limit()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_tier text;
  v_day date := (now() at time zone 'Africa/Lagos')::date;
  v_used integer;
begin
  if auth.uid() is null or auth.uid() <> new.user_id then
    raise exception 'You must be signed in to upload a Story.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(new.user_id::text, 0));
  if exists(select 1 from public.premium_memberships pm where pm.user_id=new.user_id and pm.premium_until>now())
     or public.match_plus_active_tier() in ('quarterly','annual') then
    return new;
  end if;
  v_tier:=public.match_plus_active_tier();
  if v_tier='plus' then
    insert into public.match_plus_daily_usage(user_id,usage_day,stories_created)
    values(new.user_id,v_day,1)
    on conflict(user_id,usage_day) do update
      set stories_created=public.match_plus_daily_usage.stories_created+1
      where public.match_plus_daily_usage.stories_created<3
    returning stories_created into v_used;
    if v_used is null then raise exception 'STORY_DAILY_LIMIT: Match Plus includes up to 3 Stories each day.'; end if;
    return new;
  end if;
  if exists(select 1 from public.stories st where st.user_id=new.user_id and st.created_at>now()-interval '24 hours') then
    raise exception using errcode='P0001',
      message='FREE_STORY_LIMIT: Free members can post one individual Story item every 24 hours. Upgrade to Match Plus for more Stories.';
  end if;
  return new;
end;
$$;
