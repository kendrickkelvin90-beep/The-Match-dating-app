-- The Match Lite: separate 30-day entitlement; never grants Premium-only messaging/tools.
create table if not exists public.lite_memberships (
  user_id uuid primary key references auth.users(id) on delete cascade,
  lite_started_at timestamptz not null default now(),
  lite_until timestamptz not null,
  created_at timestamptz not null default now()
);
alter table public.lite_memberships enable row level security;
drop policy if exists "Members can view their own Lite membership" on public.lite_memberships;
create policy "Members can view their own Lite membership"
  on public.lite_memberships for select to authenticated
  using (auth.uid() = user_id);
revoke insert, update, delete on public.lite_memberships from anon, authenticated;
grant select on public.lite_memberships to authenticated;

create or replace function public.is_match_lite(p_user_id uuid)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.lite_memberships lm
    where lm.user_id = p_user_id and lm.lite_until > now()
  );
$$;
revoke all on function public.is_match_lite(uuid) from public;
grant execute on function public.is_match_lite(uuid) to authenticated;

alter table public.premium_payment_requests
  drop constraint if exists premium_payment_requests_plan_check;
alter table public.premium_payment_requests
  add constraint premium_payment_requests_plan_check
  check (plan = any (array['monthly','yearly','lite_monthly']::text[]));
alter table public.premium_payment_requests
  drop constraint if exists premium_payment_plan_amount_check;
alter table public.premium_payment_requests
  add constraint premium_payment_plan_amount_check
  check (
    (plan = 'monthly' and amount_ngn = any(array[3000,5000]::integer[]))
    or (plan = 'yearly' and amount_ngn = any(array[20000,50000]::integer[]))
    or (plan = 'lite_monthly' and amount_ngn = 1000)
  );

drop policy if exists "Premium members can view likes they receive" on public.likes;
create policy "Premium or Lite members can view likes they receive"
  on public.likes for select to authenticated
  using (auth.uid() = liked_id and (public.is_match_premium(auth.uid()) or public.is_match_lite(auth.uid())));

create or replace function public.enforce_daily_swipe_limit()
returns trigger
language plpgsql security definer
set search_path = ''
as $function$
declare
  v_user uuid;
  v_swipes_today integer;
  v_premium_until timestamptz;
  v_lite_until timestamptz;
begin
  if tg_table_name = 'likes' then v_user := new.liker_id;
  else v_user := new.passer_id;
  end if;
  if auth.uid() is null or auth.uid() <> v_user then
    raise exception 'You can only swipe as yourself.';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(v_user::text, 0));
  select pm.premium_until into v_premium_until
    from public.premium_memberships pm where pm.user_id = v_user;
  if v_premium_until is not null and v_premium_until > now() then return new; end if;
  select lm.lite_until into v_lite_until
    from public.lite_memberships lm where lm.user_id = v_user;
  if v_lite_until is not null and v_lite_until > now() then return new; end if;
  select count(*)::integer into v_swipes_today
    from public.match_swipe_history h
   where h.user_id = v_user
     and h.created_at >= (date_trunc('day', now() at time zone 'Africa/Lagos') at time zone 'Africa/Lagos');
  if v_swipes_today >= 20 then
    raise exception 'DAILY_SWIPE_LIMIT: Free members can make 20 swipes per day. Upgrade to The Match Lite for unlimited swipes.';
  end if;
  return new;
end;
$function$;

create or replace function public.admin_review_match_request(p_table text, p_id uuid, p_decision text)
returns void
language plpgsql security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
  v_plan text;
  v_display_name text;
  v_now timestamptz := now();
  v_premium_until timestamptz;
  v_lite_until timestamptz;
begin
  if not public.is_match_admin() then raise exception 'Admin access denied'; end if;
  if p_table = 'verification_requests' then
    if p_decision not in ('approved','rejected') then raise exception 'Invalid verification decision'; end if;
    update public.verification_requests set status=p_decision, reviewed_at=v_now
      where id=p_id and status='pending' returning user_id into v_user_id;
    if v_user_id is null then raise exception 'Pending verification request not found'; end if;
    if p_decision='approved' then
      update public.profiles set is_verified=true, verification_level='basic', updated_at=v_now where id=v_user_id;
    end if;
  elsif p_table = 'premium_payment_requests' then
    if p_decision not in ('approved','rejected') then raise exception 'Invalid payment decision'; end if;
    update public.premium_payment_requests set status=p_decision, reviewed_at=v_now
      where id=p_id and status='pending' returning user_id, plan into v_user_id, v_plan;
    if v_user_id is null then raise exception 'Pending membership payment request not found'; end if;
    select coalesce(nullif(btrim(display_name),''),'there') into v_display_name
      from public.profiles where id=v_user_id;
    if p_decision='approved' and v_plan='lite_monthly' then
      insert into public.lite_memberships(user_id,lite_started_at,lite_until)
      values(v_user_id,v_now,v_now+interval '30 days')
      on conflict(user_id) do update set
        lite_started_at=case when public.lite_memberships.lite_until <= v_now then v_now else public.lite_memberships.lite_started_at end,
        lite_until=greatest(public.lite_memberships.lite_until,v_now)+interval '30 days'
      returning lite_until into v_lite_until;
      insert into public.notifications(user_id,type,title,body)
      values(v_user_id,'lite_welcome','The Match Lite is active!',
        'Hello '||coalesce(v_display_name,'there')||', your 30-day The Match Lite membership is now active until '||
        to_char(v_lite_until at time zone 'Africa/Lagos','DD Mon YYYY, HH12:MI AM')||
        ' (WAT). You now have unlimited swipes and can see who likes you.');
    elsif p_decision='approved' then
      insert into public.premium_memberships(user_id,premium_started_at,premium_until)
      values(v_user_id,v_now,v_now+case when v_plan='yearly' then interval '1 year' else interval '1 month' end)
      on conflict(user_id) do update set
        premium_started_at=case when public.premium_memberships.premium_until is null or public.premium_memberships.premium_until<=v_now then v_now else public.premium_memberships.premium_started_at end,
        premium_until=greatest(coalesce(public.premium_memberships.premium_until,v_now),v_now)+case when v_plan='yearly' then interval '1 year' else interval '1 month' end
      returning premium_until into v_premium_until;
      insert into public.notifications(user_id,type,title,body)
      values(v_user_id,'premium_welcome','Welcome to The Match Premium!',
        'Hello '||coalesce(v_display_name,'there')||', your '||case when v_plan='yearly' then 'yearly' else 'monthly' end||
        ' Premium subscription is now active. It expires on '||
        to_char(v_premium_until at time zone 'Africa/Lagos','DD Mon YYYY, HH12:MI AM')||' (WAT). Enjoy your exclusive benefits!');
    else
      insert into public.notifications(user_id,type,title,body)
      values(v_user_id,'verification_rejected','Membership payment not approved',
        'Hello '||coalesce(v_display_name,'there')||', your membership payment request was not approved. Please check your payment details or contact support.');
    end if;
  elsif p_table = 'member_reports' then
    if p_decision not in ('reviewed','actioned') then raise exception 'Invalid report decision'; end if;
    update public.member_reports set status=p_decision where id=p_id and status='pending';
    if not found then raise exception 'Pending member report not found'; end if;
  else raise exception 'Unsupported review table';
  end if;
end;
$function$;
