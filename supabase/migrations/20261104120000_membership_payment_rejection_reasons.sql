-- Membership payment review: persist rejection reasons and use a dedicated notification type.
-- Source migration only; it has not been applied to the live database.

drop function if exists public.admin_review_match_request(text, uuid, text);

create function public.admin_review_match_request(
  p_table text,
  p_id uuid,
  p_decision text,
  p_admin_note text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid;
  v_plan text;
  v_display_name text;
  v_reason text := nullif(pg_catalog.btrim(p_admin_note), '');
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
    if p_decision='rejected' and v_reason is null then raise exception 'A rejection reason is required'; end if;
    if v_reason is not null and pg_catalog.char_length(v_reason)>1000 then raise exception 'Rejection reason must be 1,000 characters or fewer'; end if;

    update public.premium_payment_requests
       set status=p_decision, reviewed_at=v_now,
           admin_note=case when p_decision='rejected' then v_reason else null end
     where id=p_id and status='pending'
     returning user_id,plan into v_user_id,v_plan;
    if v_user_id is null then raise exception 'Pending membership payment request not found'; end if;
    select coalesce(nullif(pg_catalog.btrim(display_name),''),'there')
      into v_display_name from public.profiles where id=v_user_id;

    if p_decision='approved' and v_plan='lite_monthly' then
      insert into public.lite_memberships(user_id,lite_started_at,lite_until)
      values(v_user_id,v_now,v_now+interval '30 days')
      on conflict(user_id) do update set
        lite_started_at=case when public.lite_memberships.lite_until<=v_now then v_now else public.lite_memberships.lite_started_at end,
        lite_until=greatest(public.lite_memberships.lite_until,v_now)+interval '30 days'
      returning lite_until into v_lite_until;
      insert into public.notifications(user_id,type,title,body)
      values(v_user_id,'premium_welcome','The Match Lite is active!',
        'Hello '||coalesce(v_display_name,'there')||', your 30-day The Match Lite membership is now active until '||
        pg_catalog.to_char(v_lite_until at time zone 'Africa/Lagos','DD Mon YYYY, HH12:MI AM')||
        ' (WAT). You now have unlimited swipes and can see who likes you.');

    elsif p_decision='approved' then
      insert into public.premium_memberships(user_id,premium_started_at,premium_until)
      values(v_user_id,v_now,v_now+case when v_plan='yearly' then interval '1 year' when v_plan='weekly' then interval '7 days' else interval '1 month' end)
      on conflict(user_id) do update set
        premium_started_at=case when public.premium_memberships.premium_until is null or public.premium_memberships.premium_until<=v_now then v_now else public.premium_memberships.premium_started_at end,
        premium_until=greatest(coalesce(public.premium_memberships.premium_until,v_now),v_now)+case when v_plan='yearly' then interval '1 year' when v_plan='weekly' then interval '7 days' else interval '1 month' end
      returning premium_until into v_premium_until;
      insert into public.notifications(user_id,type,title,body)
      values(v_user_id,'premium_welcome','Welcome to The Match Premium!',
        'Hello '||coalesce(v_display_name,'there')||', your '||case when v_plan='yearly' then 'yearly' when v_plan='weekly' then 'weekly' else 'monthly' end||
        ' Premium subscription is now active. It expires on '||
        pg_catalog.to_char(v_premium_until at time zone 'Africa/Lagos','DD Mon YYYY, HH12:MI AM')||' (WAT). Enjoy your exclusive benefits!');
    else
      insert into public.notifications(user_id,type,title,body)
      values(v_user_id,'membership_payment_rejected','Membership payment not approved',
        'Hello '||coalesce(v_display_name,'there')||', your membership payment was not approved. Reason: '||v_reason||
        '. Please correct the issue and submit a new payment request if needed.');
    end if;

  elsif p_table = 'member_reports' then
    if p_decision not in ('reviewed','actioned') then raise exception 'Invalid report decision'; end if;
    update public.member_reports set status=p_decision where id=p_id and status='pending';
    if not found then raise exception 'Pending member report not found'; end if;
  else
    raise exception 'Unsupported review table';
  end if;
end;
$function$;

revoke all on function public.admin_review_match_request(text,uuid,text,text) from public,anon;
grant execute on function public.admin_review_match_request(text,uuid,text,text) to authenticated,service_role;
