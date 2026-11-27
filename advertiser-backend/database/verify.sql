-- Run after database/bootstrap.sql in the existing Match Supabase project.
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
     or has_table_privilege('advertiser','public.advertising_campaigns','insert')
     or has_table_privilege('advertiser','public.advertising_campaigns','delete') then
    raise exception 'Campaign table grants are broader than expected';
  end if;

  if has_table_privilege('advertiser','public.advertising_impressions','select')
     or has_table_privilege('advertiser','public.advertising_clicks','select')
     or has_table_privilege('advertiser','public.advertising_unique_clicks','select')
     or has_table_privilege('advertiser','public.advertising_admins','select')
     or has_table_privilege('advertiser','public.advertising_admin_audit','select') then
    raise exception 'Private analytics/admin tables are exposed to advertiser clients';
  end if;

  if has_table_privilege('authenticated','public.advertiser_profiles','select')
     or has_table_privilege('authenticated','public.advertising_campaigns','select')
     or has_function_privilege('authenticated','public.get_my_advertising_campaign_metrics(uuid)','execute') then
    raise exception 'Ordinary member role has access to advertiser-only records or metrics';
  end if;

  if exists (
    select 1 from pg_catalog.pg_trigger t
    join pg_catalog.pg_class c on c.oid=t.tgrelid
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='auth' and c.relname='users'
      and t.tgname='on_advertiser_auth_user_created' and not t.tgisinternal
  ) then
    raise exception 'Advertiser profile creation trigger must not be attached to auth.users';
  end if;

  if (select p.prosecdef from pg_catalog.pg_proc p
      where p.oid='private.custom_access_token_hook(jsonb)'::regprocedure) then
    raise exception 'Advertiser Auth hook must run with explicit supabase_auth_admin grants, not SECURITY DEFINER';
  end if;

  if not has_function_privilege('advertiser','public.get_my_advertising_campaign_metrics(uuid)','execute')
     or has_function_privilege('anon','public.get_my_advertising_campaign_metrics(uuid)','execute') then
    raise exception 'Campaign metrics RPC execute grants are incorrect';
  end if;


  if has_function_privilege('anon','public.create_advertising_campaign(uuid,text,text,text,text,integer,text,timestamptz,text,timestamptz)','execute')
     or has_function_privilege('advertiser','public.create_advertising_campaign(uuid,text,text,text,text,integer,text,timestamptz,text,timestamptz)','execute')
     or not has_function_privilege('service_role','public.create_advertising_campaign(uuid,text,text,text,text,integer,text,timestamptz,text,timestamptz)','execute') then
    raise exception 'Campaign creation RPC must be service-role only';
  end if;

  if has_function_privilege('anon','public.submit_advertising_payment(uuid,uuid,integer,text,text)','execute')
     or has_function_privilege('advertiser','public.submit_advertising_payment(uuid,uuid,integer,text,text)','execute')
     or not has_function_privilege('service_role','public.submit_advertising_payment(uuid,uuid,integer,text,text)','execute') then
    raise exception 'Payment submission RPC must be service-role only';
  end if;

  if has_function_privilege('anon','public.admin_confirm_advertising_payment(uuid,uuid,text)','execute')
     or has_function_privilege('advertiser','public.admin_confirm_advertising_payment(uuid,uuid,text)','execute')
     or not has_function_privilege('service_role','public.admin_confirm_advertising_payment(uuid,uuid,text)','execute') then
    raise exception 'Payment confirmation RPC must be service-role only';
  end if;

  if has_function_privilege('anon','public.record_advertising_event(uuid,text,text)','execute')
     or has_function_privilege('advertiser','public.record_advertising_event(uuid,text,text)','execute')
     or not has_function_privilege('service_role','public.record_advertising_event(uuid,text,text)','execute') then
    raise exception 'Advertising event writer must be service-role only';
  end if;

  if not has_function_privilege('advertiser','private.is_advertising_admin()','execute')
     or has_function_privilege('anon','private.is_advertising_admin()','execute') then
    raise exception 'Private admin helper grants are incorrect';
  end if;


  if has_function_privilege('anon','public.create_advertising_design_request(uuid,text,uuid,text,text)','execute')
     or has_function_privilege('advertiser','public.create_advertising_design_request(uuid,text,uuid,text,text)','execute')
     or not has_function_privilege('service_role','public.create_advertising_design_request(uuid,text,uuid,text,text)','execute') then
    raise exception 'Design request RPC must be service-role only';
  end if;

  if has_function_privilege('anon','public.admin_confirm_advertising_design_payment(uuid,uuid,text)','execute')
     or has_function_privilege('advertiser','public.admin_confirm_advertising_design_payment(uuid,uuid,text)','execute')
     or not has_function_privilege('service_role','public.admin_confirm_advertising_design_payment(uuid,uuid,text)','execute') then
    raise exception 'Design payment confirmation RPC must be service-role only';
  end if;

  if has_function_privilege('advertiser','private.process_advertising_campaign_clock_cron()','execute')
     or has_function_privilege('anon','private.process_advertising_campaign_clock_cron()','execute') then
    raise exception 'Scheduler entrypoint must not be executable by app users';
  end if;

  if exists (
    select 1
    from pg_catalog.pg_class c
    join pg_catalog.pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public'
      and c.relkind in ('r','v','m')
      and c.relname not like 'advertising_%'
      and c.relname <> 'advertiser_profiles'
      and (
        has_table_privilege('advertiser',c.oid,'select')
        or has_table_privilege('advertiser',c.oid,'insert')
        or has_table_privilege('advertiser',c.oid,'update')
        or has_table_privilege('advertiser',c.oid,'delete')
      )
  ) then
    raise exception 'Advertiser role has a direct grant on a non-advertising Match table or view';
  end if;

  if has_table_privilege('advertiser','public.profiles','select')
     or has_table_privilege('advertiser','public.profiles','insert')
     then
    raise exception 'Advertiser role has access to Match member data';
  end if;

  if not has_schema_privilege('advertiser','auth','usage')
     or not has_function_privilege('advertiser','auth.uid()','execute')
     or not has_function_privilege('advertiser','auth.jwt()','execute') then
    raise exception 'Advertiser role is missing the minimum Supabase Auth helper access';
  end if;

  if pg_has_role('advertiser','authenticated','member')
     or pg_has_role('advertiser','anon','member')
     or not pg_has_role('authenticator','advertiser','member') then
    raise exception 'Advertiser database role membership is not isolated correctly';
  end if;

  if not has_function_privilege('supabase_auth_admin','private.custom_access_token_hook(jsonb)','execute') then
    raise exception 'Supabase Auth cannot execute the advertiser access-token hook';
  end if;

  if exists (
    select 1 from pg_catalog.pg_proc p
    join pg_catalog.pg_namespace n on n.oid=p.pronamespace
    where n.nspname in ('public','private')
      and has_function_privilege('advertiser',p.oid,'execute')
      and p.oid not in (
        'private.is_advertising_admin()'::regprocedure,
        'public.get_my_advertising_campaign_metrics(uuid)'::regprocedure
      )
  ) then
    raise exception 'Advertiser role can execute an unrelated Match database function';
  end if;

  if not has_schema_privilege('advertiser','private','usage') then
    raise exception 'Authenticated role cannot execute the private admin helper used by RLS';
  end if;

  if not (select relrowsecurity from pg_catalog.pg_class
          where oid='public.advertising_campaign_change_requests'::regclass)
     or not has_table_privilege('advertiser','public.advertising_campaign_change_requests','select')
     or has_table_privilege('advertiser','public.advertising_campaign_change_requests','insert')
     or has_table_privilege('advertiser','public.advertising_campaign_change_requests','update')
     or has_table_privilege('advertiser','public.advertising_campaign_change_requests','delete')
     or has_table_privilege('anon','public.advertising_campaign_change_requests','select')
     or not has_table_privilege('service_role','public.advertising_campaign_change_requests','select')
     or not has_table_privilege('service_role','public.advertising_campaign_change_requests','insert')
     or not has_table_privilege('service_role','public.advertising_campaign_change_requests','update')
     or not has_table_privilege('service_role','public.advertising_campaign_change_requests','delete') then
    raise exception 'Campaign change requests must be owner-readable and service-role writable under RLS';
  end if;

  if has_function_privilege('anon','public.request_advertising_campaign_change(uuid,uuid,text,text,text,text,text,timestamptz,text)','execute')
     or has_function_privilege('advertiser','public.request_advertising_campaign_change(uuid,uuid,text,text,text,text,text,timestamptz,text)','execute')
     or not has_function_privilege('service_role','public.request_advertising_campaign_change(uuid,uuid,text,text,text,text,text,timestamptz,text)','execute')
     or has_function_privilege('anon','public.attach_advertising_change_creative(uuid,uuid,text,text,text,text,bigint,numeric,integer,integer)','execute')
     or has_function_privilege('advertiser','public.attach_advertising_change_creative(uuid,uuid,text,text,text,text,bigint,numeric,integer,integer)','execute')
     or not has_function_privilege('service_role','public.attach_advertising_change_creative(uuid,uuid,text,text,text,text,bigint,numeric,integer,integer)','execute')
     or has_function_privilege('anon','public.admin_review_advertising_campaign_change(uuid,uuid,boolean,text)','execute')
     or has_function_privilege('advertiser','public.admin_review_advertising_campaign_change(uuid,uuid,boolean,text)','execute')
     or not has_function_privilege('service_role','public.admin_review_advertising_campaign_change(uuid,uuid,boolean,text)','execute') then
    raise exception 'Campaign change lifecycle RPCs must be service-role only';
  end if;
end;
$verify$;

select
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  has_table_privilege('advertiser', c.oid, 'select') as authenticated_has_select,
  has_table_privilege('advertiser', c.oid, 'insert') as authenticated_has_insert,
  has_table_privilege('advertiser', c.oid, 'update') as authenticated_has_update
from pg_catalog.pg_class c
join pg_catalog.pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname like 'advertising_%'
order by c.relname;
