-- Increase the Free Discover allowance from 10 to 20 total swipes per Lagos calendar day.
-- Like and Pass remain combined; active Premium members remain unlimited.
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

  if v_swipes_today >= 20 then
    raise exception 'DAILY_SWIPE_LIMIT: Free members can make 20 swipes per day. Upgrade to Premium for unlimited swipes.';
  end if;

  return new;
end;
$$;
