-- Free membership allowance is 10 total Discover swipes per Lagos calendar day.
-- A swipe means either Like or Pass. Premium remains unlimited.
create or replace function public.enforce_daily_swipe_limit()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid;
  v_swipes_today integer;
  v_premium_until timestamptz;
begin
  if tg_table_name = 'likes' then
    v_user := new.liker_id;
  else
    v_user := new.passer_id;
  end if;

  if auth.uid() is null or auth.uid() <> v_user then
    raise exception 'You can only swipe as yourself.';
  end if;

  -- Serialize a member's swipe writes so simultaneous taps cannot exceed the limit.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text, 0));

  select pm.premium_until into v_premium_until
  from public.premium_memberships pm
  where pm.user_id = v_user;

  if v_premium_until is not null and v_premium_until > now() then
    return new;
  end if;

  select count(*)::integer into v_swipes_today
  from public.match_swipe_history h
  where h.user_id = v_user
    and h.created_at >= (
      date_trunc('day', now() at time zone 'Africa/Lagos')
      at time zone 'Africa/Lagos'
    );

  if v_swipes_today >= 10 then
    raise exception 'DAILY_SWIPE_LIMIT: Free members can make only 10 swipes per day. Upgrade to Premium for unlimited swipes.';
  end if;

  return new;
end;
$$;

-- Replace the old Like-only cap with the total swipe cap.
drop trigger if exists enforce_daily_like_limit_trigger on public.likes;
create trigger enforce_daily_swipe_limit_on_like
before insert on public.likes
for each row execute function public.enforce_daily_swipe_limit();

-- Apply the same cap to Pass inserts and Pass upserts that refresh created_at.
drop trigger if exists enforce_daily_swipe_limit_on_pass on public.profile_passes;
create trigger enforce_daily_swipe_limit_on_pass
before insert or update of created_at on public.profile_passes
for each row execute function public.enforce_daily_swipe_limit();

revoke all on function public.enforce_daily_swipe_limit() from public, anon, authenticated;

create or replace function public.get_my_daily_swipe_count()
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.match_swipe_history h
  where h.user_id = auth.uid()
    and auth.uid() is not null
    and h.created_at >= (
      date_trunc('day', now() at time zone 'Africa/Lagos')
      at time zone 'Africa/Lagos'
    );
$$;

revoke all on function public.get_my_daily_swipe_count() from public, anon;
grant execute on function public.get_my_daily_swipe_count() to authenticated;
