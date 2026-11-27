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
  recorded_at timestamptz not null default now(),
  unique (campaign_id, viewer_day_key, event_day)
);
create index if not exists advertising_clicks_campaign_day_idx
  on public.advertising_clicks(campaign_id, event_day);

create table if not exists public.advertising_refunds (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.advertising_campaigns(id) on delete restrict,
  payment_id uuid not null references public.advertising_payments(id) on delete restrict,
  advertiser_id uuid not null references public.advertiser_profiles(user_id) on delete restrict,
  amount_ngn integer not null check (amount_ngn > 0),
  reason text not null check (char_length(btrim(reason)) between 3 and 500),
  status text not null default 'requested'
    check (status in ('requested','approved','paid','rejected')),
  requested_at timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references public.advertising_admins(user_id),
  paid_at timestamptz,
  bank_transfer_reference text
);

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
  public.advertising_clicks, public.advertising_refunds,
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
revoke all on public.advertising_impressions, public.advertising_clicks,
  public.advertising_admin_audit, public.advertising_admins
from anon, authenticated;

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

  return query
  select c.id, c.status, c.payment_status, c.package_days, c.go_live_at, c.ends_at,
    v_impressions, v_clicks, v_clicks,
    case when v_impressions = 0 then 0::numeric
      else round((v_clicks::numeric / v_impressions::numeric) * 100, 2) end
  from public.advertising_campaigns c where c.id = p_campaign_id;
end;
$function$;
revoke all on function public.get_my_advertising_campaign_metrics(uuid) from public, anon;
grant execute on function public.get_my_advertising_campaign_metrics(uuid) to authenticated;

-- Identity columns are written only by trusted server functions.
grant usage, select on all sequences in schema public to service_role;

commit;
