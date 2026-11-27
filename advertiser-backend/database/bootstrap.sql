-- The Match sponsored advertising bootstrap for the EXISTING Match Supabase project.
-- Apply only after the shared-project security review and regression tests pass.
-- This script preserves current anon/authenticated function access while isolating
-- advertiser sessions behind a dedicated Postgres role. Do not run before approval.
begin;

create schema if not exists private;

-- Advertiser sessions use the supported Auth role "anon" plus a custom
-- user_role claim. The pre-request guard and restrictive RLS policies prevent
-- those sessions from accessing Match member data.
set local search_path = public;
revoke all on schema private from public, anon;
grant usage on schema public, private to supabase_auth_admin;
grant usage on schema private to authenticated, service_role;
revoke usage on schema private from public, anon;
grant usage on schema auth to anon, authenticated, authenticator, service_role;
grant execute on function auth.uid(), auth.jwt() to anon, authenticated, authenticator, service_role;

-- A signed-in advertiser receives the dedicated Postgres role only after Auth
-- confirms the account was created for advertising and it has no dating profile.
create table if not exists private.advertiser_auth_registry (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table private.advertiser_auth_registry enable row level security;
revoke all on private.advertiser_auth_registry from public, anon, authenticated, service_role;
grant select on private.advertiser_auth_registry to supabase_auth_admin;
drop policy if exists advertiser_auth_hook_registry_access on private.advertiser_auth_registry;
create policy advertiser_auth_hook_registry_access on private.advertiser_auth_registry
  for all to supabase_auth_admin using (true) with check (true);

-- Auth hook may inspect only profile IDs to prevent a dating-member account
-- from being silently converted into an advertiser account.
grant usage on schema public to supabase_auth_admin;
grant select (id) on public.profiles to supabase_auth_admin;
drop policy if exists advertiser_auth_hook_member_profile_guard on public.profiles;
create policy advertiser_auth_hook_member_profile_guard on public.profiles
  for select to supabase_auth_admin using (true);

-- Trusted enrollment entrypoint. Only the server-side advertiser-register
-- Edge Function may call this function with its service-role client.
create or replace function public.register_advertiser_account(p_user_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $register$
declare
  v_email_confirmed_at timestamptz;
begin
  select u.email_confirmed_at into v_email_confirmed_at
  from auth.users u
  where u.id = p_user_id
  for update;

  if not found or v_email_confirmed_at is null then
    raise exception 'A verified Auth account is required';
  end if;

  if exists (select 1 from public.profiles p where p.id = p_user_id) then
    raise exception 'A Match member account cannot be enrolled as an advertiser';
  end if;

  insert into private.advertiser_auth_registry(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  return true;
end;
$register$;

revoke all on function public.register_advertiser_account(uuid)
  from public, anon, authenticated;
grant execute on function public.register_advertiser_account(uuid) to service_role;

create or replace function private.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $hook$
declare
  v_user_id uuid := nullif(event->>'user_id','')::uuid;
  v_claims jsonb := coalesce(event->'claims','{}'::jsonb);
begin
  -- Never grant advertiser privileges from user-editable user_metadata.
  -- A trusted server-side enrollment endpoint inserts the user into this
  -- protected registry only after verifying the session, email and member profile.
  if v_user_id is not null and exists (
    select 1 from private.advertiser_auth_registry r where r.user_id=v_user_id
  ) and not exists (
    select 1 from public.profiles p where p.id=v_user_id
  ) then
    v_claims := jsonb_set(v_claims,'{user_role}',to_jsonb('advertiser'::text),true);
    v_claims := jsonb_set(v_claims,'{role}',to_jsonb('anon'::text),true);
  end if;

  return jsonb_build_object('claims',v_claims);
end;
$hook$;
revoke all on function private.custom_access_token_hook(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function private.custom_access_token_hook(jsonb) to supabase_auth_admin;

-- Public-schema wrapper is the Supabase Dashboard Auth Hook entrypoint.
-- The implementation remains private and executable only by supabase_auth_admin.
create or replace function public.custom_access_token_hook(event jsonb)
returns jsonb
language sql
set search_path = ''
as $wrapper$
  select private.custom_access_token_hook(event);
$wrapper$;
revoke all on function public.custom_access_token_hook(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.custom_access_token_hook(jsonb) to supabase_auth_admin;

revoke all on schema private from public, anon;
grant usage on schema public, private to supabase_auth_admin;
grant usage on schema private to authenticated, service_role;

create table if not exists public.advertising_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

-- Existing Match administrators retain their normal member account/session.
-- The advertising Edge Function checks this separate allowlist for admin-only actions.
insert into public.advertising_admins(user_id)
select user_id from public.app_admins
on conflict (user_id) do nothing;

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
  status text not null default 'awaiting_payment'
    check (status in ('awaiting_payment','submitted','confirmed','rejected','duplicate','refunded')),
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
  accepted_at timestamptz,
  delivered_storage_key text,
  admin_note text,
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
  status text not null default 'awaiting_payment'
    check (status in ('awaiting_payment','submitted','confirmed','rejected','duplicate','refunded')),
  submitted_at timestamptz,
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

-- Advertiser profiles are created by the authenticated advertising API.
-- Never attach a trigger to auth.users: normal Match member signups must not
-- create advertiser records.

-- Admin reads and mutations are served through the trusted advertising Edge Function.
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

-- Advertiser Data API surface: read-only campaign and design request lists.
-- Other advertising reads/writes are performed by the trusted Edge Function.
grant select on public.advertising_campaigns, public.advertising_design_requests to anon;
grant select on public.advertising_admins to service_role;
grant all on public.advertiser_profiles, public.advertising_campaigns,
  public.advertising_creatives, public.advertising_payments,
  public.advertising_design_requests, public.advertising_design_payments, public.advertising_impressions,
  public.advertising_clicks, public.advertising_unique_clicks, public.advertising_refunds,
  public.advertising_admins, public.advertising_admin_audit to service_role;

drop policy if exists advertiser_profile_owner_read on public.advertiser_profiles;
create policy advertiser_profile_owner_read on public.advertiser_profiles
  for select to anon using (user_id = (select auth.uid()));
drop policy if exists advertiser_profile_owner_update on public.advertiser_profiles;
create policy advertiser_profile_owner_update on public.advertiser_profiles
  for update to anon using (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));

drop policy if exists advertising_campaign_owner_read on public.advertising_campaigns;
create policy advertising_campaign_owner_read on public.advertising_campaigns
  for select to anon using (
    coalesce((select auth.jwt()->>'user_role'),'') = 'advertiser'
    and advertiser_id = (select auth.uid())
  );
drop policy if exists advertising_creative_owner_read on public.advertising_creatives;
create policy advertising_creative_owner_read on public.advertising_creatives
  for select to anon using (
    exists (select 1 from public.advertising_campaigns c
      where c.id = campaign_id and c.advertiser_id = (select auth.uid()))
  );
drop policy if exists advertising_payment_owner_read on public.advertising_payments;
create policy advertising_payment_owner_read on public.advertising_payments
  for select to anon using (advertiser_id = (select auth.uid()));
drop policy if exists advertising_design_owner_read on public.advertising_design_requests;
create policy advertising_design_owner_read on public.advertising_design_requests
  for select to anon using (
    coalesce((select auth.jwt()->>'user_role'),'') = 'advertiser'
    and advertiser_id = (select auth.uid())
  );
drop policy if exists advertising_design_payment_owner_read on public.advertising_design_payments;
create policy advertising_design_payment_owner_read on public.advertising_design_payments
  for select to anon using (advertiser_id = (select auth.uid()));
drop policy if exists advertising_refund_owner_read on public.advertising_refunds;
create policy advertising_refund_owner_read on public.advertising_refunds
  for select to anon using (advertiser_id = (select auth.uid()));

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


create or replace function private.process_advertising_campaign_clock_cron()
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if session_user <> 'postgres' then
    raise exception 'Only the database scheduler may run this maintenance function' using errcode = '42501';
  end if;
  perform set_config('request.jwt.claims','{"role":"service_role"}',true);
  perform public.process_advertising_campaign_clock();
end;
$function$;
revoke all on function private.process_advertising_campaign_clock_cron() from public, anon, authenticated, service_role;
grant execute on function private.process_advertising_campaign_clock_cron() to postgres;

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
  -- Serialize events per member/campaign so parallel requests cannot bypass rolling caps.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_campaign_id::text || ':' || p_viewer_day_key, 0)
  );
  if p_event_type = 'impression' then
    if exists (
      select 1 from public.advertising_impressions
      where campaign_id=p_campaign_id and viewer_day_key=p_viewer_day_key
        and recorded_at > now() - interval '24 hours'
    ) then
      return false;
    end if;
    insert into public.advertising_impressions(campaign_id,viewer_day_key,event_day)
    values (p_campaign_id,p_viewer_day_key,v_today)
    on conflict do nothing;
    get diagnostics v_inserted = row_count;
  else
    -- Count every click, but only one unique click per member/campaign in any rolling 24h.
    insert into public.advertising_clicks(campaign_id,viewer_day_key,event_day)
    values (p_campaign_id,p_viewer_day_key,v_today);
    if exists (
      select 1 from public.advertising_unique_clicks
      where campaign_id=p_campaign_id and viewer_day_key=p_viewer_day_key
        and first_clicked_at > now() - interval '24 hours'
    ) then
      v_inserted := 0;
    else
      insert into public.advertising_unique_clicks(campaign_id,viewer_day_key,event_day)
      values (p_campaign_id,p_viewer_day_key,v_today)
      on conflict do nothing;
      get diagnostics v_inserted = row_count;
    end if;
  end if;
  return v_inserted = 1;
end;
$function$;
revoke all on function public.record_advertising_event(uuid,text,text) from public, anon, authenticated;
grant execute on function public.record_advertising_event(uuid,text,text) to service_role;




create or replace function public.create_advertising_design_request(
  p_advertiser_id uuid,
  p_service_type text,
  p_campaign_id uuid,
  p_brief text,
  p_payment_reference text
)
returns table (request_id uuid, payment_id uuid, fee_ngn integer, payment_reference text)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_fee integer;
  v_revisions integer;
  v_request uuid;
  v_payment uuid;
begin
  perform private.require_advertising_service_role();
  if not exists (select 1 from public.advertiser_profiles a where a.user_id = p_advertiser_id) then
    raise exception 'Advertiser profile not found' using errcode = '23503';
  end if;
  if p_service_type not in ('basic','premium','redesign')
     or char_length(btrim(coalesce(p_brief,''))) < 10
     or char_length(btrim(p_brief)) > 3000
     or char_length(coalesce(p_payment_reference,'')) not between 12 and 80 then
    raise exception 'Invalid design request details' using errcode = '22023';
  end if;
  if p_campaign_id is not null and not exists (
    select 1 from public.advertising_campaigns c
    where c.id = p_campaign_id and c.advertiser_id = p_advertiser_id
  ) then
    raise exception 'Campaign does not belong to this advertiser' using errcode = '42501';
  end if;
  v_fee := case p_service_type when 'basic' then 5000 when 'premium' then 10000 else 3000 end;
  v_revisions := case when p_service_type = 'redesign' then 1 else 2 end;
  insert into public.advertising_design_requests(
    advertiser_id,campaign_id,service_type,fee_ngn,status,
    revisions_allowed,revisions_used,brief
  ) values (
    p_advertiser_id,p_campaign_id,p_service_type,v_fee,'awaiting_payment',
    v_revisions,0,btrim(p_brief)
  ) returning id into v_request;
  insert into public.advertising_design_payments(
    design_request_id,advertiser_id,amount_ngn,payment_reference,status
  ) values (
    v_request,p_advertiser_id,v_fee,p_payment_reference,'awaiting_payment'
  ) returning id into v_payment;
  return query select v_request,v_payment,v_fee,p_payment_reference;
end;
$function$;
revoke all on function public.create_advertising_design_request(uuid,text,uuid,text,text) from public, anon, authenticated;
grant execute on function public.create_advertising_design_request(uuid,text,uuid,text,text) to service_role;

create or replace function public.submit_advertising_design_payment(
  p_advertiser_id uuid,
  p_payment_id uuid,
  p_bank_transfer_reference text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_payment public.advertising_design_payments%rowtype;
begin
  perform private.require_advertising_service_role();
  select * into v_payment from public.advertising_design_payments
  where id = p_payment_id and advertiser_id = p_advertiser_id for update;
  if not found or v_payment.status <> 'awaiting_payment'
     or char_length(btrim(coalesce(p_bank_transfer_reference,''))) < 4
     or char_length(p_bank_transfer_reference) > 120 then
    raise exception 'Design payment cannot be submitted' using errcode = '22023';
  end if;
  update public.advertising_design_payments
  set status = 'submitted', bank_transfer_reference = btrim(p_bank_transfer_reference),
      submitted_at = now()
  where id = p_payment_id;
  return true;
end;
$function$;
revoke all on function public.submit_advertising_design_payment(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.submit_advertising_design_payment(uuid,uuid,text) to service_role;

create or replace function public.admin_confirm_advertising_design_payment(
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
  v_payment public.advertising_design_payments%rowtype;
begin
  perform private.require_advertising_service_role();
  if not exists (select 1 from public.advertising_admins a where a.user_id = p_admin_id) then
    raise exception 'Advertising admin access denied' using errcode = '42501';
  end if;
  select * into v_payment from public.advertising_design_payments where id = p_payment_id for update;
  if not found or v_payment.status <> 'submitted' then
    raise exception 'Design payment is not awaiting confirmation' using errcode = '22023';
  end if;
  update public.advertising_design_payments
  set status = 'confirmed', confirmed_at = now(), confirmed_by = p_admin_id,
      admin_note = left(coalesce(p_admin_note,''),500)
  where id = p_payment_id;
  update public.advertising_design_requests set status = 'paid'
  where id = v_payment.design_request_id and status = 'awaiting_payment';
  insert into public.advertising_admin_audit(actor_id,action,entity_type,entity_id,details)
  values (p_admin_id,'confirm_design_payment','design_payment',p_payment_id::text,
    jsonb_build_object('design_request_id',v_payment.design_request_id,'amount_ngn',v_payment.amount_ngn));
  return true;
end;
$function$;
revoke all on function public.admin_confirm_advertising_design_payment(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.admin_confirm_advertising_design_payment(uuid,uuid,text) to service_role;

create or replace function public.advertiser_request_design_revision(
  p_advertiser_id uuid,
  p_request_id uuid
)
returns integer
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request public.advertising_design_requests%rowtype;
begin
  perform private.require_advertising_service_role();
  select * into v_request from public.advertising_design_requests
  where id = p_request_id and advertiser_id = p_advertiser_id for update;
  if not found or v_request.status <> 'first_draft_sent'
     or v_request.revisions_used >= v_request.revisions_allowed then
    raise exception 'No revision is currently available' using errcode = '22023';
  end if;
  update public.advertising_design_requests
  set status = 'revision', revisions_used = revisions_used + 1
  where id = p_request_id;
  return v_request.revisions_used + 1;
end;
$function$;
revoke all on function public.advertiser_request_design_revision(uuid,uuid) from public, anon, authenticated;
grant execute on function public.advertiser_request_design_revision(uuid,uuid) to service_role;

create or replace function public.admin_update_advertising_design_request(
  p_admin_id uuid,
  p_request_id uuid,
  p_status text,
  p_delivery_at timestamptz default null,
  p_delivered_storage_key text default null,
  p_admin_note text default null
)
returns text
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_request public.advertising_design_requests%rowtype;
begin
  perform private.require_advertising_service_role();
  if not exists (select 1 from public.advertising_admins a where a.user_id = p_admin_id) then
    raise exception 'Advertising admin access denied' using errcode = '42501';
  end if;
  select * into v_request from public.advertising_design_requests where id = p_request_id for update;
  if not found then raise exception 'Design request not found' using errcode = 'P0002'; end if;

  if p_status = 'in_progress' then
    if v_request.status <> 'paid' or p_delivery_at is null or p_delivery_at <= now() then
      raise exception 'Confirm payment and agree a future delivery deadline before starting work' using errcode = '22023';
    end if;
    update public.advertising_design_requests
    set status = 'in_progress', accepted_at = now(), agreed_delivery_at = p_delivery_at,
        admin_note = left(coalesce(p_admin_note,''),1000)
    where id = p_request_id;
  elsif p_status = 'first_draft_sent' then
    if v_request.status not in ('in_progress','revision') then raise exception 'Design is not in progress' using errcode = '22023'; end if;
    update public.advertising_design_requests set status = 'first_draft_sent',
      admin_note = left(coalesce(p_admin_note,''),1000) where id = p_request_id;
  elsif p_status = 'completed' then
    if v_request.status not in ('in_progress','first_draft_sent','revision')
       or p_delivered_storage_key is null
       or p_delivered_storage_key not like 'advertising-designs/' || v_request.advertiser_id::text || '/' || p_request_id::text || '/%'
       or position('..' in p_delivered_storage_key) > 0 then
      raise exception 'A valid private delivery asset is required before completion' using errcode = '22023';
    end if;
    update public.advertising_design_requests set status = 'completed',
      delivered_storage_key = p_delivered_storage_key,
      admin_note = left(coalesce(p_admin_note,''),1000) where id = p_request_id;
  elsif p_status = 'cancelled' then
    if v_request.status <> 'awaiting_payment' then raise exception 'Request cannot be cancelled after payment' using errcode = '22023'; end if;
    update public.advertising_design_requests set status = 'cancelled',
      admin_note = left(coalesce(p_admin_note,''),1000) where id = p_request_id;
  else
    raise exception 'Unsupported design request status' using errcode = '22023';
  end if;
  insert into public.advertising_admin_audit(actor_id,action,entity_type,entity_id,details)
  values (p_admin_id,'design_request_' || p_status,'design_request',p_request_id::text,
    jsonb_build_object('delivery_at',p_delivery_at,'delivered_storage_key',p_delivered_storage_key));
  return p_status;
end;
$function$;
revoke all on function public.admin_update_advertising_design_request(uuid,uuid,text,timestamptz,text,text) from public, anon, authenticated;
grant execute on function public.admin_update_advertising_design_request(uuid,uuid,text,timestamptz,text,text) to service_role;

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


create or replace function public.cancel_unpaid_advertising_campaign(
  p_advertiser_id uuid,
  p_campaign_id uuid
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_campaign public.advertising_campaigns%rowtype;
begin
  perform private.require_advertising_service_role();
  select * into v_campaign from public.advertising_campaigns
  where id = p_campaign_id and advertiser_id = p_advertiser_id for update;
  if not found or v_campaign.status <> 'awaiting_payment'
     or v_campaign.payment_status <> 'awaiting_payment'
     or exists (select 1 from public.advertising_payments p where p.campaign_id = p_campaign_id) then
    raise exception 'Only unpaid campaign reservations can be cancelled for free' using errcode = '22023';
  end if;
  update public.advertising_campaigns set status = 'cancelled' where id = p_campaign_id;
  return true;
end;
$function$;
revoke all on function public.cancel_unpaid_advertising_campaign(uuid,uuid) from public, anon, authenticated;
grant execute on function public.cancel_unpaid_advertising_campaign(uuid,uuid) to service_role;

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
  confirmed_campaign_payments bigint,
  confirmed_design_payments bigint,
  design_service_revenue_ngn bigint,
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
    (select count(*) from public.advertising_campaigns),
    (select count(*) from public.advertising_campaigns where status = 'active'),
    (select count(*) from public.advertising_campaigns where status in ('awaiting_payment','payment_review','awaiting_approval','scheduled')),
    (select count(*) from public.advertising_payments where status = 'confirmed'),
    (select count(*) from public.advertising_design_payments where status = 'confirmed'),
    (select coalesce(sum(amount_ngn),0)::bigint from public.advertising_design_payments where status = 'confirmed'),
    (
      (select coalesce(sum(amount_ngn),0) from public.advertising_payments where status = 'confirmed') +
      (select coalesce(sum(amount_ngn),0) from public.advertising_design_payments where status = 'confirmed')
    )::bigint;
end;
$function$;
revoke all on function public.get_advertising_admin_overview(uuid) from public, anon, authenticated;
grant execute on function public.get_advertising_admin_overview(uuid) to service_role;

create or replace function public.get_advertising_campaign_metrics(
  p_campaign_id uuid,
  p_advertiser_id uuid
)
returns table (
  campaign_id uuid, status text, payment_status text, package_days integer,
  go_live_at timestamptz, ends_at timestamptz, impressions bigint,
  clicks bigint, unique_clicks bigint, ctr numeric
)
language plpgsql stable security definer set search_path = ''
as $function$
declare
  v_owner uuid;
  v_impressions bigint;
  v_clicks bigint;
  v_unique_clicks bigint;
begin
  perform private.require_advertising_service_role();
  select c.advertiser_id into v_owner from public.advertising_campaigns c where c.id=p_campaign_id;
  if v_owner is null or (
    v_owner <> p_advertiser_id
    and not exists(select 1 from public.advertising_admins a where a.user_id=p_advertiser_id)
  ) then
    raise exception 'Campaign not found or access denied' using errcode='42501';
  end if;
  select count(*) into v_impressions from public.advertising_impressions i where i.campaign_id=p_campaign_id;
  select count(*) into v_clicks from public.advertising_clicks k where k.campaign_id=p_campaign_id;
  select count(*) into v_unique_clicks from public.advertising_unique_clicks k where k.campaign_id=p_campaign_id;
  return query select c.id,c.status,c.payment_status,c.package_days,c.go_live_at,c.ends_at,
    v_impressions,v_clicks,v_unique_clicks,
    case when v_impressions=0 then 0::numeric
      else round((v_unique_clicks::numeric/v_impressions::numeric)*100,2) end
  from public.advertising_campaigns c where c.id=p_campaign_id;
end;
$function$;
revoke all on function public.get_advertising_campaign_metrics(uuid,uuid) from public, anon, authenticated;
grant execute on function public.get_advertising_campaign_metrics(uuid,uuid) to service_role;
drop function if exists public.get_my_advertising_campaign_metrics(uuid);

-- Identity columns are written only by trusted server functions.
grant usage, select on all sequences in schema public to service_role;


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
  for select to anon using (advertiser_id = (select auth.uid()));
revoke all on public.advertising_campaign_change_requests from anon, authenticated;

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
  if v_campaign.payment_status <> 'confirmed' or v_campaign.status not in ('active','paused','scheduled')
     or (v_campaign.ends_at is not null and v_campaign.ends_at <= now()) then
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
    if v_campaign.payment_status <> 'confirmed' or v_campaign.status not in ('active','paused','scheduled')
       or (v_campaign.ends_at is not null and v_campaign.ends_at <= now()) then
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



-- Data API pre-request boundary. The Auth hook sets role=anon and
-- user_role=advertiser for advertiser accounts. Only the two read-only
-- advertiser list endpoints and the advertiser metrics RPC are allowed.
create or replace function public.match_advertiser_api_guard()
returns void
language plpgsql
set search_path = ''
as $guard$
declare
  v_path text := trim(both '/' from coalesce(current_setting('request.path', true), ''));
begin
  if coalesce((select auth.jwt()->>'user_role'), '') <> 'advertiser' then
    return;
  end if;

  if v_path in (
    'advertising_campaigns',
    'advertising_design_requests',
  ) then
    return;
  end if;

  raise sqlstate 'PGRST'
    using message = '{"code":"ADVERTISER_ACCESS_RESTRICTED","message":"Advertiser accounts can access advertising data only.","details":null,"hint":null}',
          detail = '{"status":403}';
end;
$guard$;
revoke all on function public.match_advertiser_api_guard() from public;
grant execute on function public.match_advertiser_api_guard() to anon, authenticated, service_role, authenticator;

-- Restrictive RLS boundary for every public table except the two read-only
-- advertiser list tables. This also protects GraphQL and Realtime paths that
-- do not execute the PostgREST pre-request hook.
do $boundary$
declare
  rec record;
begin
  for rec in
    select n.nspname, c.relname, c.relrowsecurity
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relkind in ('r','p')
      and c.relname not in ('advertising_campaigns','advertising_design_requests')
  loop
    if exists (
      select 1 from pg_catalog.pg_policies p
      where p.schemaname=rec.nspname and p.tablename=rec.relname
        and p.policyname='match_advertiser_data_boundary'
    ) then
      if not rec.relrowsecurity then
        execute format('alter table %I.%I enable row level security', rec.nspname, rec.relname);
      end if;
      continue;
    end if;
    if rec.relrowsecurity then
      execute format(
        'create policy match_advertiser_data_boundary on %I.%I as restrictive for all to public using ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'') with check ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'')',
        rec.nspname, rec.relname
      );
    else
      -- Enabling RLS on a previously unprotected table with this permissive
      -- policy preserves its old behavior for non-advertisers, but blocks
      -- advertiser JWTs before they can see or change member data.
      execute format('alter table %I.%I enable row level security', rec.nspname, rec.relname);
      execute format(
        'create policy match_advertiser_data_boundary on %I.%I as permissive for all to public using ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'') with check ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'')',
        rec.nspname, rec.relname
      );
    end if;
  end loop;
end;
$boundary$;

-- Direct Storage and Realtime access is not part of the advertiser portal.
-- The portal uses the private advertising B2 upload Edge Function instead.
do $service_boundaries$
begin
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists match_advertiser_data_boundary on storage.objects';
    execute 'create policy match_advertiser_data_boundary on storage.objects as restrictive for all to public using ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'') with check ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'')';
  end if;
  if to_regclass('realtime.messages') is not null then
    execute 'drop policy if exists match_advertiser_data_boundary on realtime.messages';
    execute 'create policy match_advertiser_data_boundary on realtime.messages as restrictive for all to public using ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'') with check ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'')';
  end if;
end;
$service_boundaries$;

commit;
