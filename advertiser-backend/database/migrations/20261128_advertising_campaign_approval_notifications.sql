-- Advertiser-facing campaign review notifications and payment approval guard.
alter table public.notifications drop constraint if exists notifications_type_check;
alter table public.notifications add constraint notifications_type_check check (
  type = any (array[
    'verification_approved','verification_rejected','verification_reminder',
    'verification_grace_expired','like','message','premium_welcome',
    'premium_expired','story_uploaded','story_limit','membership_payment_rejected',
    'coins_credited','coin_purchase_rejected','account_suspended','account_banned',
    'event_published','advertising_campaign_approved','advertising_campaign_rejected'
  ]::text[])
);

create or replace function public.admin_review_advertising_campaign(
  p_admin_id uuid,
  p_campaign_id uuid,
  p_approve boolean,
  p_reason text default null
)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_campaign public.advertising_campaigns%rowtype;
  v_status text;
  v_now timestamptz := now();
begin
  perform private.require_advertising_service_role();
  if not exists (select 1 from public.advertising_admins a where a.user_id = p_admin_id) then
    raise exception 'Advertising admin access denied' using errcode = '42501';
  end if;
  select * into v_campaign from public.advertising_campaigns where id = p_campaign_id for update;
  if not found or v_campaign.status not in ('awaiting_payment','payment_review','awaiting_approval')
     or v_campaign.approved_at is not null then
    raise exception 'Campaign cannot be reviewed again or is not awaiting approval' using errcode = '22023';
  end if;
  if p_approve and v_campaign.payment_status <> 'confirmed' then
    raise exception 'Campaign payment is not confirmed' using errcode = '22023';
  end if;
  if p_approve and not exists (
    select 1 from public.advertising_creatives c
    where c.campaign_id = p_campaign_id and c.is_current
  ) then
    raise exception 'Campaign has no current creative' using errcode = '22023';
  end if;
  if p_approve then
    v_status := case
      when v_campaign.payment_status <> 'confirmed' then 'awaiting_payment'
      when v_campaign.start_mode = 'scheduled' and v_campaign.scheduled_start_at > v_now then 'scheduled'
      else 'active'
    end;
    update public.advertising_campaigns
    set approved_at = v_now, approved_by = p_admin_id, rejected_at = null,
        rejection_reason = null, status = v_status,
        go_live_at = case when v_status = 'active' then v_now else null end,
        ends_at = case when v_status = 'active' then v_now + make_interval(days => package_days) else null end
    where id = p_campaign_id;
  else
    if char_length(btrim(coalesce(p_reason,''))) < 3 then
      raise exception 'A rejection reason is required' using errcode = '22023';
    end if;
    v_status := 'rejected';
    update public.advertising_campaigns
    set status = v_status, rejected_at = v_now, rejection_reason = left(btrim(p_reason),500)
    where id = p_campaign_id;
  end if;
  insert into public.advertising_admin_audit(actor_id,action,entity_type,entity_id,details)
  values (p_admin_id,case when p_approve then 'approve_campaign' else 'reject_campaign' end,
    'campaign',p_campaign_id::text,jsonb_build_object('reason',left(coalesce(p_reason,''),500)));
  return v_status;
end;
$function$;
