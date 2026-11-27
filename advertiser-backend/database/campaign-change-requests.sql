begin;

-- Advertiser-requested campaign changes are staged and require admin re-approval.
create table if not exists public.advertising_campaign_change_requests (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.advertising_campaigns(id) on delete restrict,
  advertiser_id uuid not null references public.advertiser_profiles(user_id) on delete restrict,
  proposed_headline text,
  proposed_description text,
  proposed_cta text,
  proposed_destination_url text,
  proposed_start_mode text,
  proposed_scheduled_start_at timestamptz,
  proposed_creative_id uuid references public.advertising_creatives(id) on delete restrict,
  advertiser_reason text not null check (char_length(btrim(advertiser_reason)) between 3 and 500),
  status text not null default 'pending' check (status in ('pending','approved','rejected','cancelled')),
  admin_reason text,
  reviewed_by uuid references public.advertising_admins(user_id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists advertising_campaign_one_pending_change_idx
  on public.advertising_campaign_change_requests(campaign_id) where status = 'pending';
create index if not exists advertising_change_requests_admin_queue_idx
  on public.advertising_campaign_change_requests(status, created_at desc);
alter table public.advertising_campaign_change_requests enable row level security;
drop policy if exists advertising_change_requests_select_own on public.advertising_campaign_change_requests;
create policy advertising_change_requests_select_own on public.advertising_campaign_change_requests
  for select to authenticated using (
    advertiser_id = (select auth.uid()) or private.is_advertising_admin()
  );
revoke all on public.advertising_campaign_change_requests from anon, authenticated;
grant select on public.advertising_campaign_change_requests to authenticated;
grant select, insert, update, delete on public.advertising_campaign_change_requests to service_role;

create or replace function public.request_advertising_campaign_change(
  p_advertiser_id uuid, p_campaign_id uuid, p_headline text default null,
  p_description text default null, p_cta text default null,
  p_destination_url text default null, p_start_mode text default null,
  p_scheduled_start_at timestamptz default null, p_reason text default null
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare v_campaign public.advertising_campaigns%rowtype; v_id uuid;
begin
  perform private.require_advertising_service_role();
  select * into v_campaign from public.advertising_campaigns
   where id=p_campaign_id and advertiser_id=p_advertiser_id for update;
  if not found then raise exception 'Campaign not found' using errcode='42501'; end if;
  if v_campaign.payment_status <> 'confirmed' or v_campaign.status not in ('active','paused','scheduled') then
    raise exception 'Only paid, approved campaigns that have not ended can be changed' using errcode='22023';
  end if;
  if char_length(btrim(coalesce(p_reason,''))) < 3 then
    raise exception 'A reason is required' using errcode='22023';
  end if;
  if p_headline is not null and char_length(btrim(p_headline)) not between 3 and 90 then raise exception 'Invalid headline'; end if;
  if p_description is not null and char_length(btrim(p_description)) not between 1 and 500 then raise exception 'Invalid description'; end if;
  if p_cta is not null and p_cta not in ('learn_more','visit_website','contact_us','whatsapp') then raise exception 'Invalid CTA'; end if;
  if p_destination_url is not null and (char_length(p_destination_url) not between 8 and 2048 or p_destination_url !~ '^https://') then raise exception 'Invalid destination'; end if;
  if p_start_mode is not null or p_scheduled_start_at is not null then
    if v_campaign.go_live_at is not null then raise exception 'A live campaign schedule cannot be changed'; end if;
    if coalesce(p_start_mode,v_campaign.start_mode) <> 'scheduled'
       or coalesce(p_scheduled_start_at,v_campaign.scheduled_start_at) <= now() then
      raise exception 'A scheduled campaign must have a future start time';
    end if;
  end if;
  insert into public.advertising_campaign_change_requests(
    campaign_id,advertiser_id,proposed_headline,proposed_description,proposed_cta,
    proposed_destination_url,proposed_start_mode,proposed_scheduled_start_at,advertiser_reason
  ) values (
    p_campaign_id,p_advertiser_id,nullif(btrim(p_headline),''),nullif(btrim(p_description),''),
    p_cta,nullif(btrim(p_destination_url),''),p_start_mode,p_scheduled_start_at,left(btrim(p_reason),500)
  ) returning id into v_id;
  return v_id;
end;
$function$;
revoke all on function public.request_advertising_campaign_change(uuid,uuid,text,text,text,text,text,timestamptz,text) from public,anon,authenticated;
grant execute on function public.request_advertising_campaign_change(uuid,uuid,text,text,text,text,text,timestamptz,text) to service_role;

create or replace function public.attach_advertising_change_creative(
  p_advertiser_id uuid,p_change_request_id uuid,p_creative_type text,p_storage_key text,
  p_poster_storage_key text,p_content_type text,p_byte_size bigint,p_duration_seconds numeric,
  p_width integer default null,p_height integer default null
) returns uuid
language plpgsql security definer set search_path = ''
as $function$
declare v_request public.advertising_campaign_change_requests%rowtype; v_id uuid;
begin
  perform private.require_advertising_service_role();
  select * into v_request from public.advertising_campaign_change_requests
   where id=p_change_request_id and advertiser_id=p_advertiser_id for update;
  if not found or v_request.status <> 'pending' or v_request.proposed_creative_id is not null then
    raise exception 'Change request is unavailable for creative upload' using errcode='22023';
  end if;
  if p_storage_key not like 'advertising/' || p_advertiser_id::text || '/' || v_request.campaign_id::text || '/%'
     or position('..' in p_storage_key)>0 then raise exception 'Invalid creative object key'; end if;
  if p_poster_storage_key is not null and (
     p_poster_storage_key not like 'advertising/' || p_advertiser_id::text || '/' || v_request.campaign_id::text || '/%'
     or position('..' in p_poster_storage_key)>0) then raise exception 'Invalid poster object key'; end if;
  insert into public.advertising_creatives(campaign_id,creative_type,storage_key,poster_storage_key,
    content_type,byte_size,duration_seconds,width,height,is_current)
  values(v_request.campaign_id,p_creative_type,p_storage_key,p_poster_storage_key,
    p_content_type,p_byte_size,p_duration_seconds,p_width,p_height,false) returning id into v_id;
  update public.advertising_campaign_change_requests set proposed_creative_id=v_id where id=v_request.id;
  return v_id;
end;
$function$;
revoke all on function public.attach_advertising_change_creative(uuid,uuid,text,text,text,text,bigint,numeric,integer,integer) from public,anon,authenticated;
grant execute on function public.attach_advertising_change_creative(uuid,uuid,text,text,text,text,bigint,numeric,integer,integer) to service_role;

create or replace function public.admin_review_advertising_campaign_change(
  p_admin_id uuid,p_change_request_id uuid,p_approve boolean,p_reason text default null
) returns text
language plpgsql security definer set search_path = ''
as $function$
declare v_request public.advertising_campaign_change_requests%rowtype;
        v_campaign public.advertising_campaigns%rowtype; v_status text;
begin
  perform private.require_advertising_service_role();
  if not exists(select 1 from public.advertising_admins where user_id=p_admin_id) then
    raise exception 'Advertising admin access denied' using errcode='42501';
  end if;
  select * into v_request from public.advertising_campaign_change_requests where id=p_change_request_id for update;
  if not found or v_request.status <> 'pending' then raise exception 'Change request is not pending'; end if;
  select * into v_campaign from public.advertising_campaigns where id=v_request.campaign_id for update;
  if not found then raise exception 'Campaign not found'; end if;
  if p_approve then
    if v_campaign.payment_status <> 'confirmed' or v_campaign.status not in ('active','paused','scheduled') then
      raise exception 'Campaign is no longer eligible for changes' using errcode='22023';
    end if;
    if v_request.proposed_creative_id is not null then
      update public.advertising_creatives set is_current=false where campaign_id=v_campaign.id and is_current;
      update public.advertising_creatives set is_current=true
       where id=v_request.proposed_creative_id and campaign_id=v_campaign.id;
      if not found then raise exception 'Proposed creative is unavailable'; end if;
    end if;
    update public.advertising_campaigns set
      headline=coalesce(v_request.proposed_headline,headline),
      description=coalesce(v_request.proposed_description,description),
      cta=coalesce(v_request.proposed_cta,cta),
      destination_url=coalesce(v_request.proposed_destination_url,destination_url),
      start_mode=coalesce(v_request.proposed_start_mode,start_mode),
      scheduled_start_at=coalesce(v_request.proposed_scheduled_start_at,scheduled_start_at),
      status=case when go_live_at is null and coalesce(v_request.proposed_start_mode,start_mode)='scheduled'
                   and coalesce(v_request.proposed_scheduled_start_at,scheduled_start_at)>now() then 'scheduled'
                  else status end
    where id=v_campaign.id;
    v_status := 'approved';
  else
    if char_length(btrim(coalesce(p_reason,'')))<3 then raise exception 'A rejection reason is required'; end if;
    if v_request.proposed_creative_id is not null then
      update public.advertising_creatives set is_current=false where id=v_request.proposed_creative_id;
    end if;
    v_status := 'rejected';
  end if;
  update public.advertising_campaign_change_requests set status=v_status,
    admin_reason=left(coalesce(p_reason,''),500),reviewed_by=p_admin_id,reviewed_at=now()
  where id=p_change_request_id;
  insert into public.advertising_admin_audit(actor_id,action,entity_type,entity_id,details)
  values(p_admin_id,'review_campaign_change','campaign_change_request',p_change_request_id::text,
    jsonb_build_object('approved',p_approve,'campaign_id',v_campaign.id,'reason',left(coalesce(p_reason,''),500)));
  return v_status;
end;
$function$;
revoke all on function public.admin_review_advertising_campaign_change(uuid,uuid,boolean,text) from public,anon,authenticated;
grant execute on function public.admin_review_advertising_campaign_change(uuid,uuid,boolean,text) to service_role;

commit;
