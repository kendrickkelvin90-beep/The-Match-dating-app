-- Allow advertisers to remove their own campaigns from Discover without erasing payment/audit history.
-- Campaign rows and related payment records are retained; the deleted status is excluded from ad serving.
alter table public.advertising_campaigns
  drop constraint if exists advertising_campaigns_status_check;

alter table public.advertising_campaigns
  add constraint advertising_campaigns_status_check
  check (status in (
    'draft','awaiting_payment','payment_review','awaiting_approval','scheduled',
    'active','paused','completed','expired_unpaid','rejected','cancelled','deleted'
  ));

create or replace function public.delete_advertising_campaign(
  p_advertiser_id uuid,
  p_campaign_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_campaign_id uuid;
begin
  perform private.require_advertising_service_role();

  update public.advertising_campaigns
  set status = 'deleted',
      updated_at = now()
  where id = p_campaign_id
    and advertiser_id = p_advertiser_id
    and status <> 'deleted'
  returning id into v_campaign_id;

  if v_campaign_id is null then
    raise exception 'Campaign not found, not owned by advertiser, or already deleted'
      using errcode = 'P0002';
  end if;

  return true;
end;
$function$;

revoke all on function public.delete_advertising_campaign(uuid,uuid) from public, anon, authenticated;
grant execute on function public.delete_advertising_campaign(uuid,uuid) to service_role;
