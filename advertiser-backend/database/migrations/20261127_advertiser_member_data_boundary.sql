-- The Match advertiser/member isolation boundary.
-- This migration is additive: it does not alter the existing member signup hook.
-- Apply only after reviewing the matching shared-project bootstrap and tests.

begin;

-- Prevent race-condition account conversion. Both advertiser enrollment and
-- member profile creation lock the same auth.users row before checking the
-- protected registry, so only one account type can win.
create or replace function private.prevent_advertiser_member_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
begin
  perform 1 from auth.users u where u.id = new.id for update;

  if exists (
    select 1 from private.advertiser_auth_registry r
    where r.user_id = new.id
  ) then
    raise exception 'Advertiser accounts cannot create Match member profiles'
      using errcode = '23514';
  end if;

  return new;
end;
$function$;

revoke all on function private.prevent_advertiser_member_profile()
  from public, anon, authenticated, service_role;

drop trigger if exists prevent_advertiser_member_profile on public.profiles;
create trigger prevent_advertiser_member_profile
before insert on public.profiles
for each row execute function private.prevent_advertiser_member_profile();

-- Restrict advertiser JWTs from all public tables except the two read-only
-- advertiser list resources. Existing member policies remain intact.
do $boundary$
declare rec record;
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
      where p.schemaname=rec.nspname
        and p.tablename=rec.relname
        and p.policyname='match_advertiser_data_boundary'
    ) then
      continue;
    end if;

    if rec.relrowsecurity then
      execute format(
        'create policy match_advertiser_data_boundary on %I.%I as restrictive for all to public using ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'') with check ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'')',
        rec.nspname, rec.relname
      );
    else
      execute format('alter table %I.%I enable row level security', rec.nspname, rec.relname);
      execute format(
        'create policy match_advertiser_data_boundary on %I.%I as permissive for all to public using ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'') with check ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'')',
        rec.nspname, rec.relname
      );
    end if;
  end loop;
end;
$boundary$;

-- Advertiser sessions must not use member Storage or Realtime channels.
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



-- Admin operations are served only by the trusted Edge Function. Advertisers
-- can directly read only their own campaign/design list rows.
drop policy if exists advertiser_profile_owner_read on public.advertiser_profiles;
create policy advertiser_profile_owner_read on public.advertiser_profiles
for select to anon using (user_id=(select auth.uid()));
drop policy if exists advertising_campaign_owner_read on public.advertising_campaigns;
create policy advertising_campaign_owner_read on public.advertising_campaigns
for select to anon using (
 coalesce((select auth.jwt()->>'user_role'),'')='advertiser'
 and advertiser_id=(select auth.uid())
);
drop policy if exists advertising_creative_owner_read on public.advertising_creatives;
create policy advertising_creative_owner_read on public.advertising_creatives
for select to anon using (
 exists(select 1 from public.advertising_campaigns c
 where c.id=campaign_id and c.advertiser_id=(select auth.uid()))
);
drop policy if exists advertising_payment_owner_read on public.advertising_payments;
create policy advertising_payment_owner_read on public.advertising_payments
for select to anon using (advertiser_id=(select auth.uid()));
drop policy if exists advertising_design_owner_read on public.advertising_design_requests;
create policy advertising_design_owner_read on public.advertising_design_requests
for select to anon using (
 coalesce((select auth.jwt()->>'user_role'),'')='advertiser'
 and advertiser_id=(select auth.uid())
);
drop policy if exists advertising_design_payment_owner_read on public.advertising_design_payments;
create policy advertising_design_payment_owner_read on public.advertising_design_payments
for select to anon using (advertiser_id=(select auth.uid()));
drop policy if exists advertising_refund_owner_read on public.advertising_refunds;
create policy advertising_refund_owner_read on public.advertising_refunds
for select to anon using (advertiser_id=(select auth.uid()));
drop policy if exists advertising_change_requests_select_own on public.advertising_campaign_change_requests;
create policy advertising_change_requests_select_own on public.advertising_campaign_change_requests
for select to anon using (advertiser_id=(select auth.uid()));

revoke all on public.advertising_creatives,public.advertising_payments,
 public.advertising_design_payments,public.advertising_refunds,
 public.advertising_campaign_change_requests
from anon,authenticated;
grant select on public.advertising_campaigns,public.advertising_design_requests to anon;

drop function if exists public.is_advertising_admin();
drop function if exists private.is_advertising_admin();
revoke usage on schema private from anon;

-- Existing Match administrators are the only initial advertising administrators.
-- Their member JWT remains a normal member JWT; the advertising API checks this
-- allowlist server-side for admin-only actions.
insert into public.advertising_admins(user_id)
select user_id from public.app_admins
on conflict (user_id) do nothing;

-- Analytics aggregation runs only in the trusted Edge Function with service
-- role. Do not expose a SECURITY DEFINER analytics RPC to anon advertisers.
create or replace function public.get_advertising_campaign_metrics(
  p_campaign_id uuid,
  p_advertiser_id uuid
)
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
  perform private.require_advertising_service_role();
  select c.advertiser_id into v_owner
  from public.advertising_campaigns c
  where c.id = p_campaign_id;

  if v_owner is null or (
    v_owner <> p_advertiser_id
    and not exists (select 1 from public.advertising_admins a where a.user_id=p_advertiser_id)
  ) then
    raise exception 'Campaign not found or access denied' using errcode = '42501';
  end if;

  select count(*) into v_impressions from public.advertising_impressions i where i.campaign_id=p_campaign_id;
  select count(*) into v_clicks from public.advertising_clicks k where k.campaign_id=p_campaign_id;
  select count(*) into v_unique_clicks from public.advertising_unique_clicks k where k.campaign_id=p_campaign_id;

  return query
  select c.id,c.status,c.payment_status,c.package_days,c.go_live_at,c.ends_at,
    v_impressions,v_clicks,v_unique_clicks,
    case when v_impressions=0 then 0::numeric
      else round((v_unique_clicks::numeric/v_impressions::numeric)*100,2) end
  from public.advertising_campaigns c where c.id=p_campaign_id;
end;
$function$;
revoke all on function public.get_advertising_campaign_metrics(uuid,uuid)
  from public, anon, authenticated;
grant execute on function public.get_advertising_campaign_metrics(uuid,uuid)
  to service_role;

-- The earlier public RPC is no longer used and must not be callable by anon.
revoke all on function public.get_my_advertising_campaign_metrics(uuid)
  from public, anon, authenticated, service_role;

commit;
