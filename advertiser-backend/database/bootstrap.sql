-- The Match Advertiser Project — isolated database bootstrap
-- Run ONLY in the separate advertiser Supabase project.
-- Never run this in the production Match member project.
begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated, service_role;

create table if not exists public.advertising_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists public.advertiser_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  advertiser_type text not null check (advertiser_type in ('individual','business')),
  display_name text not null check (char_length(btrim(display_name)) between 2 and 140),
  contact_name text,
  phone text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.advertising_campaigns (
  id uuid primary key default gen_random_uuid(),
  advertiser_id uuid not null references public.advertiser_profiles(user_id) on delete restrict,
  headline text not null check (char_length(btrim(headline)) between 3 and 90),
  description text not null check (char_length(btrim(description)) between 1 and 500),
  cta text not null check (cta in ('learn_more','visit_website','contact_us','whatsapp')),
  destination_url text not null check (char_length(destination_url) between 8 and 2048),
  package_days integer not null check (package_days in (7,14,30)),
  package_price_ngn integer not null check (
    (package_days = 7 and package_price_ngn = 12000) or
    (package_days = 14 and package_price_ngn = 22000) or
    (package_days = 30 and package_price_ngn = 40000)
  ),
  start_mode text not null check (start_mode in ('immediate','scheduled')),
  scheduled_start_at timestamptz,
  payment_reference text not null unique,
  payment_deadline_at timestamptz not null,
  payment_status text not null default 'awaiting_payment'
    check (payment_status in ('awaiting_payment','submitted','confirmed','rejected','refunded','duplicate')),
  status text not null default 'draft'
    check (status in ('draft','awaiting_payment','payment_review','awaiting_approval','scheduled','active','paused','completed','expired_unpaid','rejected','cancelled')),
  approved_at timestamptz,
  approved_by uuid references public.advertising_admins(user_id),
  rejected_at timestamptz,
  rejection_reason text,
  go_live_at timestamptz,
  ends_at timestamptz,
  paused_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((start_mode = 'immediate' and scheduled_start_at is null) or
         (start_mode = 'scheduled' and scheduled_start_at is not null)),
  check (ends_at is null or (go_live_at is not null and ends_at > go_live_at))
);

create index if not exists advertising_campaigns_advertiser_created_idx
  on public.advertising_campaigns(advertiser_id, created_at desc);
create index if not exists advertising_campaigns_eligible_idx
  on public.advertising_campaigns(status, go_live_at, ends_at)
  where status in ('active','scheduled');

create table if not exists public.advertising_creatives (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.advertising_campaigns(id) on delete cascade,
  creative_type text not null check (creative_type in ('image','video')),
  storage_key text not null unique,
  poster_storage_key text,
  content_type text not null,
  byte_size bigint not null check (byte_size > 0),
  duration_seconds numeric(5,2),
  width integer,
  height integer,
  is_current boolean not null default true,
  created_at timestamptz not null default now(),
  check (
    (creative_type = 'image' and content_type in ('image/jpeg','image/png','image/webp')
      and byte_size <= 10485760 and duration_seconds is null)
    or
    (creative_type = 'video' and content_type = 'video/mp4'
      and byte_size <= 20971520 and duration_seconds is not null and duration_seconds between 0.1 and 30
      and poster_storage_key is not null)
  )
);
create unique index if not exists advertising_creatives_one_current_idx
  on public.advertising_creatives(campaign_id) where is_current;

create table if not exists public.advertising_payments (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.advertising_campaigns(id) on delete restrict,
  advertiser_id uuid not null references public.advertiser_profiles(user_id) on delete restrict,
  amount_ngn integer not null check (amount_ngn > 0),
  bank_transfer_reference text,
  receipt_storage_key text,
  status text not null default 'submitted'
    check (status in ('submitted','confirmed','rejected','duplicate','refunded')),
  submitted_at timestamptz not null default now(),
  confirmed_at timestamptz,
  confirmed_by uuid references public.advertising_admins(user_id),
  admin_note text,
  created_at timestamptz not null default now()
);
create unique index if not exists advertising_payments_transfer_reference_idx
  on public.advertising_payments(lower(bank_transfer_reference))
  where bank_transfer_reference is not null and status <> 'duplicate';
create index if not exists advertising_payments_campaign_idx
  on public.advertising_payments(campaign_id, created_at desc);

create table if not exists public.advertising_design_requests (
  id uuid primary key default gen_random_uuid(),
  advertiser_id uuid not null references public.advertiser_profiles(user_id) on delete restrict,
  campaign_id uuid references public.advertising_campaigns(id) on delete set null,
  service_type text not null check (service_type in ('basic','premium','redesign')),
  fee_ngn integer not null check (
    (service_type = 'basic' and fee_ngn = 5000) or
    (service_type = 'premium' and fee_ngn = 10000) or
    (service_type = 'redesign' and fee_ngn = 3000)
  ),
  status text not null default 'awaiting_payment'
    check (status in ('awaiting_payment','paid','in_progress','first_draft_sent','revision','completed','cancelled','refunded')),
  agreed_delivery_at timestamptz,
  revisions_allowed integer not null check (
    (service_type in ('basic','premium') and revisions_allowed = 2) or
    (service_type = 'redesign' and revisions_allowed = 1)
  ),
  revisions_used integer not null default 0 check (revisions_used >= 0 and revisions_used <= revisions_allowed),
  brief text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Pseudonymous daily exposure keys only. Raw member UUIDs and sensitive member
-- profile/orientation data are never stored in advertising analytics.
create table if not exists public.advertising_design_payments (
  id uuid primary key default gen_random_uuid(),
  design_request_id uuid not null references public.advertising_design_requests(id) on delete restrict,
  advertiser_id uuid not null references public.advertiser_profiles(user_id) on delete restrict,
  amount_ngn integer not null check (amount_ngn > 0),
  payment_reference text not null unique,
  bank_transfer_reference text,
  status text not null default 'submitted'
    check (status in ('submitted','confirmed','rejected','duplicate','refunded')),
  submitted_at timestamptz not null default now(),
  confirmed_at timestamptz,
  confirmed_by uuid references public.advertising_admins(user_id),
  admin_note text
);
create unique index if not exists advertising_design_payments_transfer_reference_idx
  on public.advertising_design_payments(lower(bank_transfer_reference))
  where bank_transfer_reference is not null and status <> 'duplicate';

create table if not exists public.advertising_impressions (
  id bigint generated always as identity primary key,
  campaign_id uuid not null references public.advertising_campaigns(id) on delete cascade,
  viewer_day_key text not null check (char_length(viewer_day_key) between 32 and 128),
  event_day date not null,
  recorded_at timestamptz not null default now(),
  unique (campaign_id, viewer_day_key, event_day)
);
create index if not exists advertising_impressions_campaign_day_idx
  on public.advertising_impressions(campaign_id, event_day);

create table if not exists public.advertising_clicks (
  id bigint generated always as identity primary key,
  campaign_id uuid not null references public.advertising_campaigns(id) on delete cascade,
  viewer_day_key text not null check (char_length(viewer_day_key) between 32 and 128),
  event_day date not null,
  recorded_at timestamptz not null default now()
);
create index if not exists advertising_clicks_campaign_day_idx
  on public.advertising_clicks(campaign_id, event_day);

create table if not exists public.advertising_unique_clicks (
  id bigint generated always as identity primary key,
  campaign_id uuid not null references public.advertising_campaigns(id) on delete cascade,
  viewer_day_key text not null check (char_length(viewer_day_key) between 32 and 128),
  event_day date not null,
  first_clicked_at timestamptz not null default now(),
  unique (campaign_id, viewer_day_key, event_day)
);
create index if not exists advertising_unique_clicks_campaign_day_idx
  on public.advertising_unique_clicks(campaign_id, event_day);

create table if not exists public.advertising_refunds (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.advertising_campaigns(id) on delete restrict,
  payment_id uuid not null references public.advertising_payments(id) on delete restrict,
  advertiser_id uuid not null references public.advertiser_profiles(user_id) on delete restrict,
  amount_ngn integer not null check (amount_ngn > 0),
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  admin_note text,
  status text not null default 'requested'
    check (status in ('requested','approved','paid','rejected')),
  requested_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references public.advertising_admins(user_id),
  paid_at timestamptz,
  bank_transfer_reference text
);

create unique index if not exists advertising_refunds_one_per_payment_idx on public.advertising_refunds(payment_id);

create table if not exists public.advertising_admin_audit (
  id bigint generated always as identity primary key,
  actor_id uuid references public.advertising_admins(user_id),
  action text not null,
  entity_type text not null,
  entity_id text not null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create or replace function private.touch_advertising_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $function$
begin
  new.updated_at := now();
  return new;
end;
$function$;
revoke all on function private.touch_advertising_updated_at() from public, anon, authenticated;

drop trigger if exists advertiser_profiles_touch_updated_at on public.advertiser_profiles;
create trigger advertiser_profiles_touch_updated_at before update on public.advertiser_profiles
for each row execute function private.touch_advertising_updated_at();
drop trigger if exists advertising_campaigns_touch_updated_at on public.advertising_campaigns;
create trigger advertising_campaigns_touch_updated_at before update on public.advertising_campaigns
for each row execute function private.touch_advertising_updated_at();
drop trigger if exists advertising_design_requests_touch_updated_at on public.advertising_design_requests;
create trigger advertising_design_requests_touch_updated_at before update on public.advertising_design_requests
for each row execute function private.touch_advertising_updated_at();

create or replace function private.create_advertiser_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  insert into public.advertiser_profiles(user_id, advertiser_type, display_name)
  values (
    new.id,
    case when coalesce(new.raw_user_meta_data ->> 'advertiser_type','') = 'business' then 'business' else 'individual' end,
    case when char_length(coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(coalesce(new.email,''), '@', 1))) >= 2
      then coalesce(nullif(btrim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(coalesce(new.email,''), '@', 1))
      else 'Advertiser' end
  )
  on conflict (user_id) do nothing;
  return new;
end;
$function$;
revoke all on function private.create_advertiser_profile() from public, anon, authenticated;

drop trigger if exists on_advertiser_auth_user_created on auth.users;
create trigger on_advertiser_auth_user_created
  after insert on auth.users
  for each row execute function private.create_advertiser_profile();

create or replace function private.is_advertising_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (
    select 1 from public.advertising_admins a
    where a.user_id = (select auth.uid())
  );
$function$;
revoke all on function private.is_advertising_admin() from public, anon;
grant execute on function private.is_advertising_admin() to authenticated;

alter table public.advertising_admins enable row level security;
alter table public.advertiser_profiles enable row level security;
alter table public.advertising_campaigns enable row level security;
alter table public.advertising_creatives enable row level security;
alter table public.advertising_payments enable row level security;
alter table public.advertising_design_requests enable row level security;
alter table public.advertising_design_payments enable row level security;
alter table public.advertising_impressions enable row level security;
alter table public.advertising_clicks enable row level security;
alter table public.advertising_unique_clicks enable row level security;
alter table public.advertising_refunds enable row level security;
alter table public.advertising_admin_audit enable row level security;

revoke all on public.advertising_admins, public.advertiser_profiles,
  public.advertising_campaigns, public.advertising_creatives,
  public.advertising_payments, public.advertising_design_requests,
  public.advertising_design_payments, public.advertising_impressions, public.advertising_clicks,
  public.advertising_refunds, public.advertising_admin_audit
from anon, authenticated;

grant select on public.advertiser_profiles to authenticated;
grant update (display_name, contact_name, phone) on public.advertiser_profiles to authenticated;
grant select on public.advertising_campaigns, public.advertising_creatives,
  public.advertising_payments, public.advertising_design_requests,
  public.advertising_design_payments, public.advertising_refunds to authenticated;
grant select on public.advertising_admins to service_role;
grant all on public.advertiser_profiles, public.advertising_campaigns,
  public.advertising_creatives, public.advertising_payments,
  public.advertising_design_requests, public.advertising_design_payments, public.advertising_impressions,
  public.advertising_clicks, public.advertising_unique_clicks, public.advertising_refunds,
  public.advertising_admins, public.advertising_admin_audit to service_role;

create policy advertiser_profile_owner_read on public.advertiser_profiles
  for select to authenticated using (user_id = (select auth.uid()) or (select private.is_advertising_admin()));
create policy advertiser_profile_owner_update on public.advertiser_profiles
  for update to authenticated using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

create policy advertising_campaign_owner_read on public.advertising_campaigns
  for select to authenticated using (advertiser_id = (select auth.uid()) or (select private.is_advertising_admin()));
create policy advertising_creative_owner_read on public.advertising_creatives
  for select to authenticated using (
    exists (select 1 from public.advertising_campaigns c
      where c.id = campaign_id and (c.advertiser_id = (select auth.uid()) or (select private.is_advertising_admin())))
  );
create policy advertising_payment_owner_read on public.advertising_payments
  for select to authenticated using (advertiser_id = (select auth.uid()) or (select private.is_advertising_admin()));
create policy advertising_design_owner_read on public.advertising_design_requests
  for select to authenticated using (advertiser_id = (select auth.uid()) or (select private.is_advertising_admin()));
create policy advertising_design_payment_owner_read on public.advertising_design_payments
  for select to authenticated using (advertiser_id = (select auth.uid()) or (select private.is_advertising_admin()));
create policy advertising_refund_owner_read on public.advertising_refunds
  for select to authenticated using (advertiser_id = (select auth.uid()) or (select private.is_advertising_admin()));

-- Analytics event rows, admin audit and the admin allowlist are never exposed
-- to normal advertiser clients. Service-role server functions own all writes.
revoke all on public.advertising_impressions, public.advertising_clicks, public.advertising_unique_clicks,
  public.advertising_admin_audit, public.advertising_admins
from anon, authenticated;


-- Privileged workflow functions are callable only by server-side service-role
-- clients. The Edge Function must authenticate the user and verify ownership
-- or advertising-admin membership before invoking these RPCs.
create or replace function private.require_advertising_service_role()
returns void
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if coalesce((select auth.jwt() ->> 'role'), '') <> 'service_role' then
    raise exception 'Advertising service role required' using errcode = '42501';
  end if;
end;
$function$;
revoke all on function private.require_advertising_service_role() from public, anon, authenticated;
grant execute on function private.require_advertising_service_role() to service_role;

create or replace function public.create_advertising_campaign(
  p_advertiser_id uuid,
  p_headline text,
  p_description text,
  p_cta text,
  p_destination_url text,
  p_package_days integer,
  p_start_mode text,
  p_scheduled_start_at timestamptz,
  p_payment_reference text,
  p_payment_deadline_at timestamptz
)
returns table (campaign_id uuid, payment_reference text, payment_deadline_at timestamptz, amount_ngn integer)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_amount integer;
  v_campaign_id uuid;
begin
  perform private.require_advertising_service_role();
  if p_advertiser_id is null or not exists (
    select 1 from public.advertiser_profiles a where a.user_id = p_advertiser_id
  ) then
    raise exception 'Advertiser profile not found' using errcode = '23503';
  end if;
  if char_length(btrim(coalesce(p_headline,''))) not between 3 and 90
     or char_length(btrim(coalesce(p_description,''))) not between 1 and 500
     or p_cta not in ('learn_more','visit_website','contact_us','whatsapp')
     or p_package_days not in (7,14,30)
     or p_start_mode not in ('immediate','scheduled')
     or p_payment_reference is null or char_length(p_payment_reference) not between 12 and 80
     or p_payment_deadline_at <= now()
     or p_payment_deadline_at > now() + interval '25 hours'
     or (p_start_mode = 'immediate' and p_scheduled_start_at is not null)
     or (p_start_mode = 'scheduled' and (p_scheduled_start_at is null or p_scheduled_start_at <= now())) then
    raise exception 'Invalid campaign details' using errcode = '22023';
  end if;
  v_amount := case p_package_days when 7 then 12000 when 14 then 22000 when 30 then 40000 end;
  insert into public.advertising_campaigns(
    advertiser_id, headline, description, cta, destination_url,
    package_days, package_price_ngn, start_mode, scheduled_start_at,
    payment_reference, payment_deadline_at, payment_status, status
  ) values (
    p_advertiser_id, btrim(p_headline), btrim(p_description), p_cta, p_destination_url,
    p_package_days, v_amount, p_start_mode, p_scheduled_start_at,
    p_payment_reference, p_payment_deadline_at, 'awaiting_payment', 'awaiting_payment'
  ) returning id into v_campaign_id;
  return query select v_campaign_id, p_payment_reference, p_payment_deadline_at, v_amount;
end;
$function$;
revoke all on function public.create_advertising_campaign(uuid,text,text,text,text,integer,text,timestamptz,text,timestamptz) from public, anon, authenticated;
grant execute on function public.create_advertising_campaign(uuid,text,text,text,text,integer,text,timestamptz,text,timestamptz) to service_role;

create or replace function public.submit_advertising_payment(
  p_advertiser_id uuid,
  p_campaign_id uuid,
  p_amount_ngn integer,
  p_bank_transfer_reference text,
  p_receipt_storage_key text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_campaign public.advertising_campaigns%rowtype;
  v_payment_id uuid;
begin
  perform private.require_advertising_service_role();
  select * into v_campaign
  from public.advertising_campaigns
  where id = p_campaign_id and advertiser_id = p_advertiser_id
  for update;
  if not found then raise exception 'Campaign not found' using errcode = '42501'; end if;
  if not exists (select 1 from public.advertising_creatives c where c.campaign_id = p_campaign_id and c.is_current) then
    raise exception 'Upload an approved creative before submitting payment' using errcode = '22023';
  end if;
  if v_campaign.payment_deadline_at <= now()
     or v_campaign.status not in ('awaiting_payment','payment_review')
     or v_campaign.payment_status not in ('awaiting_payment','rejected')
     or p_amount_ngn <> v_campaign.package_price_ngn
     or char_length(btrim(coalesce(p_bank_transfer_reference,''))) < 4
     or char_length(p_bank_transfer_reference) > 120 then
    raise exception 'Payment submission is not valid for this campaign' using errcode = '22023';
  end if;
  if p_receipt_storage_key is not null and (
    p_receipt_storage_key not like 'advertisers/' || p_advertiser_id::text || '/receipts/%'
    or position('..' in p_receipt_storage_key) > 0
  ) then
    raise exception 'Invalid receipt reference' using errcode = '22023';
  end if;
  insert into public.advertising_payments(
    campaign_id, advertiser_id, amount_ngn, bank_transfer_reference,
    receipt_storage_key, status
  ) values (
    p_campaign_id, p_advertiser_id, p_amount_ngn,
    btrim(p_bank_transfer_reference), p_receipt_storage_key, 'submitted'
  ) returning id into v_payment_id;
  update public.advertising_campaigns
  set payment_status = 'submitted', status = 'payment_review'
  where id = p_campaign_id;
  return v_payment_id;
end;
$function$;
revoke all on function public.submit_advertising_payment(uuid,uuid,integer,text,text) from public, anon, authenticated;
grant execute on function public.submit_advertising_payment(uuid,uuid,integer,text,text) to service_role;

create or replace function public.admin_confirm_advertising_payment(
  p_admin_id uuid,
  p_payment_id uuid,
  p_admin_note text default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_payment public.advertising_payments%rowtype;
  v_campaign public.advertising_campaigns%rowtype;
  v_now timestamptz := now();
begin
  perform private.require_advertising_service_role();
  if not exists (select 1 from public.advertising_admins a where a.user_id = p_admin_id) then
    raise exception 'Advertising admin access denied' using errcode = '42501';
  end if;
  select * into v_payment from public.advertising_payments where id = p_payment_id for update;
  if not found or v_payment.status <> 'submitted' then
    raise exception 'Payment is not awaiting confirmation' using errcode = '22023';
  end if;
  select * into v_campaign from public.advertising_campaigns where id = v_payment.campaign_id for update;
  if not found or v_payment.amount_ngn <> v_campaign.package_price_ngn then
    raise exception 'Payment amount does not match the campaign package' using errcode = '22023';
  end if;
  update public.advertising_payments
  set status = 'confirmed', confirmed_at = v_now, confirmed_by = p_admin_id,
      admin_note = left(coalesce(p_admin_note,''),500)
  where id = p_payment_id;
  update public.advertising_campaigns
  set payment_status = 'confirmed',
      status = case
        when approved_at is null then 'awaiting_approval'
        when start_mode = 'scheduled' and scheduled_start_at > v_now then 'scheduled'
        else 'active'
      end,
      go_live_at = case
        when approved_at is not null and (start_mode = 'immediate' or scheduled_start_at <= v_now) then v_now
        else go_live_at
      end,
      ends_at = case
        when approved_at is not null and (start_mode = 'immediate' or scheduled_start_at <= v_now)
          then v_now + make_interval(days => package_days)
        else ends_at
      end
  where id = v_campaign.id;
  insert into public.advertising_admin_audit(actor_id,action,entity_type,entity_id,details)
  values (p_admin_id,'confirm_payment','payment',p_payment_id::text,
    jsonb_build_object('campaign_id',v_campaign.id,'amount_ngn',v_payment.amount_ngn));
  return true;
end;
$function$;
revoke all on function public.admin_confirm_advertising_payment(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.admin_confirm_advertising_payment(uuid,uuid,text) to service_role;

create or replace function public.admin_review_advertising_campaign(
  p_admin_id uuid,
  p_campaign_id uuid,
  p_approve boolean,
  p_reason text default null
)
returns text
language plpgsql
security definer
set search_path = ''
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
  if p_approve and not exists (select 1 from public.advertising_creatives c where c.campaign_id = p_campaign_id and c.is_current) then
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
revoke all on function public.admin_review_advertising_campaign(uuid,uuid,boolean,text) from public, anon, authenticated;
grant execute on function public.admin_review_advertising_campaign(uuid,uuid,boolean,text) to service_role;

create or replace function public.admin_set_advertising_campaign_state(
  p_admin_id uuid,
  p_campaign_id uuid,
  p_action text
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_campaign public.advertising_campaigns%rowtype;
  v_status text;
begin
  perform private.require_advertising_service_role();
  if not exists (select 1 from public.advertising_admins a where a.user_id = p_admin_id) then
    raise exception 'Advertising admin access denied' using errcode = '42501';
  end if;
  select * into v_campaign from public.advertising_campaigns where id = p_campaign_id for update;
  if not found then raise exception 'Campaign not found' using errcode = 'P0002'; end if;
  if p_action = 'pause' and v_campaign.status = 'active' then
    v_status := 'paused';
    update public.advertising_campaigns set status = v_status, paused_at = now() where id = p_campaign_id;
  elsif p_action = 'resume' and v_campaign.status = 'paused'
    and v_campaign.payment_status = 'confirmed' and v_campaign.approved_at is not null
    and v_campaign.ends_at > now() then
    v_status := 'active';
    update public.advertising_campaigns set status = v_status, paused_at = null where id = p_campaign_id;
  else
    raise exception 'Campaign cannot be changed to the requested state' using errcode = '22023';
  end if;
  insert into public.advertising_admin_audit(actor_id,action,entity_type,entity_id)
  values (p_admin_id,'campaign_' || p_action,'campaign',p_campaign_id::text);
  return v_status;
end;
$function$;
revoke all on function public.admin_set_advertising_campaign_state(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.admin_set_advertising_campaign_state(uuid,uuid,text) to service_role;



create or replace function public.replace_advertising_creative(
  p_advertiser_id uuid,
  p_campaign_id uuid,
  p_creative_type text,
  p_storage_key text,
  p_poster_storage_key text,
  p_content_type text,
  p_byte_size bigint,
  p_duration_seconds numeric,
  p_width integer default null,
  p_height integer default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_campaign public.advertising_campaigns%rowtype;
  v_id uuid;
begin
  perform private.require_advertising_service_role();
  select * into v_campaign from public.advertising_campaigns
  where id = p_campaign_id and advertiser_id = p_advertiser_id
  for update;
  if not found then raise exception 'Campaign not found' using errcode = '42501'; end if;
  if v_campaign.go_live_at is not null or v_campaign.approved_at is not null
     or v_campaign.status not in ('awaiting_payment','payment_review','awaiting_approval') then
    raise exception 'Creative changes after approval or launch require an admin-reviewed change request' using errcode = '22023';
  end if;
  if p_storage_key not like 'advertising/' || p_advertiser_id::text || '/' || p_campaign_id::text || '/%'
     or position('..' in p_storage_key) > 0
     or (p_poster_storage_key is not null and (
       p_poster_storage_key not like 'advertising/' || p_advertiser_id::text || '/' || p_campaign_id::text || '/%'
       or position('..' in p_poster_storage_key) > 0
     )) then
    raise exception 'Invalid creative object key' using errcode = '22023';
  end if;
  update public.advertising_creatives set is_current = false
  where campaign_id = p_campaign_id and is_current;
  insert into public.advertising_creatives(
    campaign_id,creative_type,storage_key,poster_storage_key,content_type,
    byte_size,duration_seconds,width,height,is_current
  ) values (
    p_campaign_id,p_creative_type,p_storage_key,p_poster_storage_key,p_content_type,
    p_byte_size,p_duration_seconds,p_width,p_height,true
  ) returning id into v_id;
  return v_id;
end;
$function$;
revoke all on function public.replace_advertising_creative(uuid,uuid,text,text,text,text,bigint,numeric,integer,integer) from public, anon, authenticated;
grant execute on function public.replace_advertising_creative(uuid,uuid,text,text,text,text,bigint,numeric,integer,integer) to service_role;

create or replace function public.process_advertising_campaign_clock()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_expired integer;
  v_started integer;
  v_completed integer;
begin
  perform private.require_advertising_service_role();

  update public.advertising_campaigns
  set status = 'expired_unpaid'
  where status = 'awaiting_payment'
    and payment_status = 'awaiting_payment'
    and payment_deadline_at <= now();
  get diagnostics v_expired = row_count;

  update public.advertising_campaigns
  set status = 'active',
      go_live_at = now(),
      ends_at = now() + make_interval(days => package_days)
  where status = 'scheduled'
    and payment_status = 'confirmed'
    and approved_at is not null
    and scheduled_start_at <= now();
  get diagnostics v_started = row_count;

  update public.advertising_campaigns
  set status = 'completed'
  where status in ('active','paused')
    and ends_at is not null
    and ends_at <= now();
  get diagnostics v_completed = row_count;

  return jsonb_build_object(
    'expired_unpaid',v_expired,
    'started',v_started,
    'completed',v_completed
  );
end;
$function$;
revoke all on function public.process_advertising_campaign_clock() from public, anon, authenticated;
grant execute on function public.process_advertising_campaign_clock() to service_role;

create or replace function public.record_advertising_event(
  p_campaign_id uuid,
  p_viewer_day_key text,
  p_event_type text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_inserted integer;
  v_today date := (now() at time zone 'Africa/Lagos')::date;
begin
  perform private.require_advertising_service_role();
  if p_event_type not in ('impression','click')
     or p_viewer_day_key is null or char_length(p_viewer_day_key) not between 32 and 128 then
    raise exception 'Invalid advertising event' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.advertising_campaigns c
    where c.id = p_campaign_id and c.status = 'active'
      and c.payment_status = 'confirmed' and c.approved_at is not null
      and c.go_live_at <= now() and c.ends_at > now()
  ) then
    return false;
  end if;
  if p_event_type = 'impression' then
    insert into public.advertising_impressions(campaign_id,viewer_day_key,event_day)
    values (p_campaign_id,p_viewer_day_key,v_today)
    on conflict do nothing;
    get diagnostics v_inserted = row_count;
  else
    insert into public.advertising_clicks(campaign_id,viewer_day_key,event_day)
    values (p_campaign_id,p_viewer_day_key,v_today);
    insert into public.advertising_unique_clicks(campaign_id,viewer_day_key,event_day)
    values (p_campaign_id,p_viewer_day_key,v_today)
    on conflict do nothing;
    get diagnostics v_inserted = row_count;
  end if;
  return v_inserted = 1;
end;
$function$;
revoke all on function public.record_advertising_event(uuid,text,text) from public, anon, authenticated;
grant execute on function public.record_advertising_event(uuid,text,text) to service_role;



create or replace function public.admin_record_duplicate_advertising_payment(
  p_admin_id uuid,
  p_campaign_id uuid,
  p_advertiser_id uuid,
  p_amount_ngn integer,
  p_bank_transfer_reference text,
  p_admin_note text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_payment_id uuid;
begin
  perform private.require_advertising_service_role();
  if not exists (select 1 from public.advertising_admins a where a.user_id = p_admin_id) then
    raise exception 'Advertising admin access denied' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.advertising_campaigns c
    where c.id = p_campaign_id and c.advertiser_id = p_advertiser_id
  ) then
    raise exception 'Campaign and advertiser do not match' using errcode = '42501';
  end if;
  if p_amount_ngn <= 0 or char_length(btrim(coalesce(p_bank_transfer_reference,''))) < 4 then
    raise exception 'Duplicate transfer details are invalid' using errcode = '22023';
  end if;
  insert into public.advertising_payments(
    campaign_id,advertiser_id,amount_ngn,bank_transfer_reference,
    status,confirmed_at,confirmed_by,admin_note
  ) values (
    p_campaign_id,p_advertiser_id,p_amount_ngn,btrim(p_bank_transfer_reference),
    'duplicate',now(),p_admin_id,left(coalesce(p_admin_note,'Verified additional/duplicate transfer'),500)
  ) returning id into v_payment_id;
  insert into public.advertising_admin_audit(actor_id,action,entity_type,entity_id,details)
  values (p_admin_id,'record_duplicate_payment','payment',v_payment_id::text,
    jsonb_build_object('campaign_id',p_campaign_id,'amount_ngn',p_amount_ngn));
  return v_payment_id;
end;
$function$;
revoke all on function public.admin_record_duplicate_advertising_payment(uuid,uuid,uuid,integer,text,text) from public, anon, authenticated;
grant execute on function public.admin_record_duplicate_advertising_payment(uuid,uuid,uuid,integer,text,text) to service_role;

create or replace function public.request_advertising_refund(
  p_advertiser_id uuid,
  p_payment_id uuid,
  p_reason text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_payment public.advertising_payments%rowtype;
  v_campaign public.advertising_campaigns%rowtype;
  v_refund_id uuid;
begin
  perform private.require_advertising_service_role();
  select * into v_payment from public.advertising_payments
  where id = p_payment_id and advertiser_id = p_advertiser_id for update;
  if not found or v_payment.status not in ('confirmed','duplicate') then
    raise exception 'This payment is not eligible for a refund request' using errcode = '22023';
  end if;
  select * into v_campaign from public.advertising_campaigns where id = v_payment.campaign_id;
  if v_payment.status <> 'duplicate'
     and (v_campaign.status <> 'rejected' or v_campaign.go_live_at is not null) then
    raise exception 'Refunds are not available after a campaign has started' using errcode = '22023';
  end if;
  if char_length(btrim(coalesce(p_reason,''))) < 3 then
    raise exception 'Please provide a refund reason' using errcode = '22023';
  end if;
  insert into public.advertising_refunds(
    campaign_id,payment_id,advertiser_id,amount_ngn,reason,status
  ) values (
    v_payment.campaign_id,v_payment.id,p_advertiser_id,v_payment.amount_ngn,
    left(btrim(p_reason),500),'requested'
  ) returning id into v_refund_id;
  return v_refund_id;
end;
$function$;
revoke all on function public.request_advertising_refund(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.request_advertising_refund(uuid,uuid,text) to service_role;

create or replace function public.admin_review_advertising_refund(
  p_admin_id uuid,
  p_refund_id uuid,
  p_approve boolean,
  p_reason text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_refund public.advertising_refunds%rowtype;
  v_status text;
begin
  perform private.require_advertising_service_role();
  if not exists (select 1 from public.advertising_admins a where a.user_id = p_admin_id) then
    raise exception 'Advertising admin access denied' using errcode = '42501';
  end if;
  select * into v_refund from public.advertising_refunds where id = p_refund_id for update;
  if not found or v_refund.status <> 'requested' then
    raise exception 'Refund is not awaiting review' using errcode = '22023';
  end if;
  if not p_approve and char_length(btrim(coalesce(p_reason,''))) < 3 then
    raise exception 'A reason is required to reject a refund' using errcode = '22023';
  end if;
  v_status := case when p_approve then 'approved' else 'rejected' end;
  update public.advertising_refunds
  set status = v_status, approved_at = case when p_approve then now() else null end,
      approved_by = p_admin_id, admin_note = case when p_approve then null else left(btrim(p_reason),500) end
  where id = p_refund_id;
  insert into public.advertising_admin_audit(actor_id,action,entity_type,entity_id,details)
  values (p_admin_id,'refund_' || v_status,'refund',p_refund_id::text,jsonb_build_object('amount_ngn',v_refund.amount_ngn));
  return v_status;
end;
$function$;
revoke all on function public.admin_review_advertising_refund(uuid,uuid,boolean,text) from public, anon, authenticated;
grant execute on function public.admin_review_advertising_refund(uuid,uuid,boolean,text) to service_role;

create or replace function public.admin_mark_advertising_refund_paid(
  p_admin_id uuid,
  p_refund_id uuid,
  p_bank_transfer_reference text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_refund public.advertising_refunds%rowtype;
  v_payment public.advertising_payments%rowtype;
begin
  perform private.require_advertising_service_role();
  if not exists (select 1 from public.advertising_admins a where a.user_id = p_admin_id) then
    raise exception 'Advertising admin access denied' using errcode = '42501';
  end if;
  select * into v_refund from public.advertising_refunds where id = p_refund_id for update;
  if not found or v_refund.status <> 'approved' or char_length(btrim(coalesce(p_bank_transfer_reference,''))) < 4 then
    raise exception 'Refund is not approved or bank reference is missing' using errcode = '22023';
  end if;
  select * into v_payment from public.advertising_payments where id = v_refund.payment_id for update;
  update public.advertising_refunds
  set status = 'paid', paid_at = now(), bank_transfer_reference = btrim(p_bank_transfer_reference)
  where id = p_refund_id;
  update public.advertising_payments set status = 'refunded' where id = v_payment.id;
  if v_payment.status = 'confirmed' then
    update public.advertising_campaigns c
    set payment_status = 'refunded'
    where c.id = v_refund.campaign_id
      and c.status = 'rejected'
      and not exists (
        select 1 from public.advertising_payments other
        where other.campaign_id = c.id and other.id <> v_payment.id and other.status = 'confirmed'
      );
  end if;
  insert into public.advertising_admin_audit(actor_id,action,entity_type,entity_id,details)
  values (p_admin_id,'refund_paid','refund',p_refund_id::text,
    jsonb_build_object('amount_ngn',v_refund.amount_ngn,'bank_transfer_reference',p_bank_transfer_reference));
  return true;
end;
$function$;
revoke all on function public.admin_mark_advertising_refund_paid(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.admin_mark_advertising_refund_paid(uuid,uuid,text) to service_role;

create or replace function public.get_advertising_admin_overview(p_admin_id uuid)
returns table (
  campaigns_total bigint,
  active_campaigns bigint,
  pending_campaigns bigint,
  confirmed_payments bigint,
  confirmed_revenue_ngn bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  perform private.require_advertising_service_role();
  if not exists (select 1 from public.advertising_admins a where a.user_id = p_admin_id) then
    raise exception 'Advertising admin access denied' using errcode = '42501';
  end if;
  return query
  select
    count(distinct c.id),
    count(distinct c.id) filter (where c.status = 'active'),
    count(distinct c.id) filter (where c.status in ('awaiting_payment','payment_review','awaiting_approval','scheduled')),
    count(distinct p.id) filter (where p.status = 'confirmed'),
    coalesce(sum(p.amount_ngn) filter (where p.status = 'confirmed'),0)::bigint
  from public.advertising_campaigns c
  full join public.advertising_payments p on p.campaign_id = c.id;
end;
$function$;
revoke all on function public.get_advertising_admin_overview(uuid) from public, anon, authenticated;
grant execute on function public.get_advertising_admin_overview(uuid) to service_role;

create or replace function public.get_my_advertising_campaign_metrics(p_campaign_id uuid)
returns table (
  campaign_id uuid,
  status text,
  payment_status text,
  package_days integer,
  go_live_at timestamptz,
  ends_at timestamptz,
  impressions bigint,
  clicks bigint,
  unique_clicks bigint,
  ctr numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_owner uuid;
  v_impressions bigint;
  v_clicks bigint;
  v_unique_clicks bigint;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required' using errcode = '28000';
  end if;

  select c.advertiser_id into v_owner
  from public.advertising_campaigns c
  where c.id = p_campaign_id;

  if v_owner is null or (v_owner <> (select auth.uid()) and not private.is_advertising_admin()) then
    raise exception 'Campaign not found or access denied' using errcode = '42501';
  end if;

  select count(*) into v_impressions
  from public.advertising_impressions i where i.campaign_id = p_campaign_id;
  select count(*) into v_clicks
  from public.advertising_clicks k where k.campaign_id = p_campaign_id;
  select count(*) into v_unique_clicks
  from public.advertising_unique_clicks k where k.campaign_id = p_campaign_id;

  return query
  select c.id, c.status, c.payment_status, c.package_days, c.go_live_at, c.ends_at,
    v_impressions, v_clicks, v_unique_clicks,
    case when v_impressions = 0 then 0::numeric
      else round((v_unique_clicks::numeric / v_impressions::numeric) * 100, 2) end
  from public.advertising_campaigns c where c.id = p_campaign_id;
end;
$function$;
revoke all on function public.get_my_advertising_campaign_metrics(uuid) from public, anon;
grant execute on function public.get_my_advertising_campaign_metrics(uuid) to authenticated;

-- Identity columns are written only by trusted server functions.
grant usage, select on all sequences in schema public to service_role;

commit;
