-- Run after database/bootstrap.sql in the existing Match Supabase project.
-- This script verifies the supported anon + user_role advertiser boundary.
do $verify$
declare
  v_table text;
begin
  foreach v_table in array array[
    'advertising_admins','advertiser_profiles','advertising_campaigns',
    'advertising_creatives','advertising_payments','advertising_design_requests',
    'advertising_design_payments','advertising_impressions','advertising_clicks',
    'advertising_unique_clicks','advertising_refunds','advertising_admin_audit',
    'advertising_campaign_change_requests'
  ] loop
    if not exists (
      select 1 from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname=v_table and c.relrowsecurity
    ) then
      raise exception 'RLS is not enabled on public.%',v_table;
    end if;
  end loop;

  if not has_table_privilege('anon','public.advertising_campaigns','select')
     or not has_table_privilege('anon','public.advertising_design_requests','select')
     or has_table_privilege('anon','public.advertiser_profiles','select')
     or has_table_privilege('anon','public.advertising_campaign_change_requests','select')
     or has_table_privilege('anon','public.advertising_admins','select')
     or has_table_privilege('anon','public.advertising_impressions','select')
     or has_table_privilege('anon','public.advertising_clicks','select')
     or has_table_privilege('anon','public.advertising_unique_clicks','select') then
    raise exception 'Advertiser Data API table grants exceed the read-only allowlist';
  end if;

  if has_table_privilege('authenticated','public.advertising_campaigns','select')
     or has_table_privilege('authenticated','public.advertising_design_requests','select')
     or has_table_privilege('authenticated','public.advertiser_profiles','select')
     or has_function_privilege('authenticated','public.get_my_advertising_campaign_metrics(uuid)','execute') then
    raise exception 'Normal member role has direct access to advertiser-only records';
  end if;

  if has_function_privilege('anon','public.create_advertising_campaign(uuid,text,text,text,text,integer,text,timestamptz,text,timestamptz)','execute')
     or not has_function_privilege('service_role','public.create_advertising_campaign(uuid,text,text,text,text,integer,text,timestamptz,text,timestamptz)','execute')
     or has_function_privilege('anon','public.submit_advertising_payment(uuid,uuid,integer,text,text)','execute')
     or not has_function_privilege('service_role','public.submit_advertising_payment(uuid,uuid,integer,text,text)','execute')
     or has_function_privilege('anon','public.admin_confirm_advertising_payment(uuid,uuid,text)','execute')
     or not has_function_privilege('service_role','public.admin_confirm_advertising_payment(uuid,uuid,text)','execute')
     or has_function_privilege('anon','public.record_advertising_event(uuid,text,text)','execute')
     or not has_function_privilege('service_role','public.record_advertising_event(uuid,text,text)','execute') then
    raise exception 'Campaign/payment/event writer RPCs must remain service-role only';
  end if;

  if not has_function_privilege('anon','public.get_my_advertising_campaign_metrics(uuid)','execute')
     or has_function_privilege('authenticated','public.get_my_advertising_campaign_metrics(uuid)','execute')
     or not has_function_privilege('anon','private.is_advertising_admin()','execute')
     or has_function_privilege('authenticated','private.is_advertising_admin()','execute') then
    raise exception 'Advertiser-only read RPC/helper grants are incorrect';
  end if;

  if has_function_privilege('anon','public.create_advertising_design_request(uuid,text,uuid,text,text)','execute')
     or not has_function_privilege('service_role','public.create_advertising_design_request(uuid,text,uuid,text,text)','execute')
     or has_function_privilege('anon','public.admin_confirm_advertising_design_payment(uuid,uuid,text)','execute')
     or not has_function_privilege('service_role','public.admin_confirm_advertising_design_payment(uuid,uuid,text)','execute') then
    raise exception 'Design workflow RPCs must remain service-role only';
  end if;

  if has_function_privilege('anon','private.process_advertising_campaign_clock_cron()','execute')
     or has_function_privilege('authenticated','private.process_advertising_campaign_clock_cron()','execute') then
    raise exception 'Scheduler entrypoint must not be executable by app users';
  end if;

  if not has_function_privilege('supabase_auth_admin','public.custom_access_token_hook(jsonb)','execute')
     or not has_function_privilege('supabase_auth_admin','private.custom_access_token_hook(jsonb)','execute')
     or has_function_privilege('anon','public.custom_access_token_hook(jsonb)','execute')
     or has_function_privilege('authenticated','public.custom_access_token_hook(jsonb)','execute') then
    raise exception 'Supabase Auth hook entrypoint grants are incorrect';
  end if;

  if (select p.prosecdef from pg_catalog.pg_proc p
      where p.oid='public.custom_access_token_hook(jsonb)'::regprocedure)
     or (select p.prosecdef from pg_catalog.pg_proc p
      where p.oid='private.custom_access_token_hook(jsonb)'::regprocedure) then
    raise exception 'Auth hook functions must run as supabase_auth_admin, not SECURITY DEFINER';
  end if;

  if not has_function_privilege('anon','public.match_advertiser_api_guard()','execute')
     or not has_function_privilege('authenticator','public.match_advertiser_api_guard()','execute')
     or not (select p.prosecdef from pg_catalog.pg_proc p
       where p.oid='public.match_advertiser_api_guard()'::regprocedure) then
    raise exception 'Advertiser Data API pre-request guard is not configured safely';
  end if;

  if not has_column_privilege('supabase_auth_admin','public.profiles','id','select')
     or not exists (
       select 1 from pg_catalog.pg_policies
       where schemaname='public' and tablename='profiles'
         and policyname='advertiser_auth_hook_member_profile_guard'
     ) then
    raise exception 'Auth hook must only be able to inspect Match profile IDs';
  end if;

  if exists (
    select 1 from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid=t.tgrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='auth' and c.relname='users'
      and not t.tgisinternal and t.tgname like '%advertiser%'
  ) then
    raise exception 'No advertiser trigger may be attached to auth.users';
  end if;

  if not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname='public' and tablename='profiles'
      and policyname='match_advertiser_data_boundary'
      and permissive='RESTRICTIVE'
  ) then
    raise exception 'Match member profile table is missing its restrictive advertiser boundary';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind in ('r','p')
      and c.relname not in ('advertising_campaigns','advertising_design_requests')
      and c.relrowsecurity
      and not exists (
        select 1 from pg_catalog.pg_policies p
        where p.schemaname='public' and p.tablename=c.relname
          and p.policyname='match_advertiser_data_boundary'
          and p.permissive='RESTRICTIVE'
      )
  ) then
    raise exception 'A public table is missing the restrictive advertiser boundary';
  end if;

  if to_regclass('storage.objects') is not null and not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname='storage' and tablename='objects'
      and policyname='match_advertiser_data_boundary'
      and permissive='RESTRICTIVE'
  ) then
    raise exception 'Storage objects are missing the advertiser isolation policy';
  end if;

  if to_regclass('realtime.messages') is not null and not exists (
    select 1 from pg_catalog.pg_policies
    where schemaname='realtime' and tablename='messages'
      and policyname='match_advertiser_data_boundary'
      and permissive='RESTRICTIVE'
  ) then
    raise exception 'Realtime messages are missing the advertiser isolation policy';
  end if;

  if not has_table_privilege('service_role','public.advertising_campaign_change_requests','select')
     or not has_table_privilege('service_role','public.advertising_campaign_change_requests','insert')
     or not has_table_privilege('service_role','public.advertising_campaign_change_requests','update')
     or not has_table_privilege('service_role','public.advertising_campaign_change_requests','delete')
     or has_table_privilege('anon','public.advertising_campaign_change_requests','select') then
    raise exception 'Campaign change requests must remain server-side only';
  end if;

  if has_function_privilege('anon','public.request_advertising_campaign_change(uuid,uuid,text,text,text,text,text,timestamptz,text)','execute')
     or not has_function_privilege('service_role','public.request_advertising_campaign_change(uuid,uuid,text,text,text,text,text,timestamptz,text)','execute')
     or has_function_privilege('anon','public.attach_advertising_change_creative(uuid,uuid,text,text,text,text,bigint,numeric,integer,integer)','execute')
     or not has_function_privilege('service_role','public.attach_advertising_change_creative(uuid,uuid,text,text,text,text,bigint,numeric,integer,integer)','execute')
     or has_function_privilege('anon','public.admin_review_advertising_campaign_change(uuid,uuid,boolean,text)','execute')
     or not has_function_privilege('service_role','public.admin_review_advertising_campaign_change(uuid,uuid,boolean,text)','execute') then
    raise exception 'Campaign change lifecycle RPCs must be service-role only';
  end if;
end;
$verify$;

select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  has_table_privilege('anon',c.oid,'select') as advertiser_anon_has_select,
  has_table_privilege('anon',c.oid,'insert') as advertiser_anon_has_insert,
  has_table_privilege('anon',c.oid,'update') as advertiser_anon_has_update
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname like 'advertising_%'
order by c.relname;
