-- Run after database/bootstrap.sql in the separate advertiser Supabase project.
-- This script raises an exception if a required isolation control is missing.
do $verify$
declare
  v_table text;
begin
  foreach v_table in array array[
    'advertising_admins',
    'advertiser_profiles',
    'advertising_campaigns',
    'advertising_creatives',
    'advertising_payments',
    'advertising_design_requests',
    'advertising_design_payments',
    'advertising_impressions',
    'advertising_clicks',
    'advertising_unique_clicks',
    'advertising_unique_clicks',
    'advertising_refunds',
    'advertising_admin_audit'
  ] loop
    if not exists (
      select 1 from pg_catalog.pg_class c
      join pg_catalog.pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public' and c.relname = v_table and c.relrowsecurity
    ) then
      raise exception 'RLS is not enabled on public.%', v_table;
    end if;
  end loop;

  if has_table_privilege('anon','public.advertising_campaigns','select')
     or has_table_privilege('anon','public.advertising_campaigns','insert')
     or has_table_privilege('authenticated','public.advertising_campaigns','insert')
     or has_table_privilege('authenticated','public.advertising_campaigns','delete') then
    raise exception 'Campaign table grants are broader than expected';
  end if;

  if has_table_privilege('authenticated','public.advertising_impressions','select')
     or has_table_privilege('authenticated','public.advertising_clicks','select')
     or has_table_privilege('authenticated','public.advertising_admins','select')
     or has_table_privilege('authenticated','public.advertising_admin_audit','select') then
    raise exception 'Private analytics/admin tables are exposed to advertiser clients';
  end if;

  if not has_function_privilege('authenticated','public.get_my_advertising_campaign_metrics(uuid)','execute')
     or has_function_privilege('anon','public.get_my_advertising_campaign_metrics(uuid)','execute') then
    raise exception 'Campaign metrics RPC execute grants are incorrect';
  end if;


  if has_function_privilege('anon','public.create_advertising_campaign(uuid,text,text,text,text,integer,text,timestamptz,text,timestamptz)','execute')
     or has_function_privilege('authenticated','public.create_advertising_campaign(uuid,text,text,text,text,integer,text,timestamptz,text,timestamptz)','execute')
     or not has_function_privilege('service_role','public.create_advertising_campaign(uuid,text,text,text,text,integer,text,timestamptz,text,timestamptz)','execute') then
    raise exception 'Campaign creation RPC must be service-role only';
  end if;

  if has_function_privilege('anon','public.submit_advertising_payment(uuid,uuid,integer,text,text)','execute')
     or has_function_privilege('authenticated','public.submit_advertising_payment(uuid,uuid,integer,text,text)','execute')
     or not has_function_privilege('service_role','public.submit_advertising_payment(uuid,uuid,integer,text,text)','execute') then
    raise exception 'Payment submission RPC must be service-role only';
  end if;

  if has_function_privilege('anon','public.admin_confirm_advertising_payment(uuid,uuid,text)','execute')
     or has_function_privilege('authenticated','public.admin_confirm_advertising_payment(uuid,uuid,text)','execute')
     or not has_function_privilege('service_role','public.admin_confirm_advertising_payment(uuid,uuid,text)','execute') then
    raise exception 'Payment confirmation RPC must be service-role only';
  end if;

  if has_function_privilege('anon','public.record_advertising_event(uuid,text,text)','execute')
     or has_function_privilege('authenticated','public.record_advertising_event(uuid,text,text)','execute')
     or not has_function_privilege('service_role','public.record_advertising_event(uuid,text,text)','execute') then
    raise exception 'Advertising event writer must be service-role only';
  end if;

  if not has_function_privilege('authenticated','private.is_advertising_admin()','execute')
     or has_function_privilege('anon','private.is_advertising_admin()','execute') then
    raise exception 'Private admin helper grants are incorrect';
  end if;

  if not has_schema_privilege('authenticated','private','usage') then
    raise exception 'Authenticated role cannot execute the private admin helper used by RLS';
  end if;
end;
$verify$;

select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  has_table_privilege('authenticated', c.oid, 'select') as authenticated_has_select,
  has_table_privilege('authenticated', c.oid, 'insert') as authenticated_has_insert,
  has_table_privilege('authenticated', c.oid, 'update') as authenticated_has_update
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname like 'advertising_%'
order by c.relname;
