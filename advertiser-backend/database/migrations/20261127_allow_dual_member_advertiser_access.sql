-- Allow one verified Match Auth identity to use both the dating app and advertiser portal.
-- Advertiser-only identities remain isolated; dual-role members retain authenticated access.
begin;

create or replace function public.is_dual_member_advertiser()
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select exists (select 1 from public.profiles p where p.id = (select auth.uid()));
$function$;
revoke all on function public.is_dual_member_advertiser() from public;
grant execute on function public.is_dual_member_advertiser() to anon, authenticated, authenticator, service_role;

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
  from auth.users u where u.id = p_user_id for update;

  if not found or v_email_confirmed_at is null then
    raise exception 'A verified Auth account is required';
  end if;

  insert into private.advertiser_auth_registry(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  return true;
end;
$register$;
revoke all on function public.register_advertiser_account(uuid) from public, anon, authenticated;
grant execute on function public.register_advertiser_account(uuid) to service_role;

-- An advertiser can also complete Match dating registration. This removes only
-- the advertising-specific profile-creation blocker; normal Match signup rules remain.
drop trigger if exists prevent_advertiser_member_profile on public.profiles;

create or replace function private.custom_access_token_hook(event jsonb)
returns jsonb
language plpgsql
set search_path = ''
as $hook$
declare
  v_user_id uuid := nullif(event->>'user_id','')::uuid;
  v_claims jsonb := coalesce(event->'claims','{}'::jsonb);
begin
  if v_user_id is not null and exists (
    select 1 from private.advertiser_auth_registry r where r.user_id = v_user_id
  ) then
    v_claims := jsonb_set(v_claims,'{user_role}',to_jsonb('advertiser'::text),true);
    -- Preserve the normal authenticated Postgres role for existing Match members.
    -- New advertiser-only accounts stay isolated in anon until they create a member profile.
    if not exists (select 1 from public.profiles p where p.id = v_user_id) then
      v_claims := jsonb_set(v_claims,'{role}',to_jsonb('anon'::text),true);
    end if;
  end if;
  return jsonb_build_object('claims',v_claims);
end;
$hook$;
revoke all on function private.custom_access_token_hook(jsonb) from public, anon, authenticated, service_role;
grant execute on function private.custom_access_token_hook(jsonb) to supabase_auth_admin;

-- Both database roles may read only their own advertiser rows. Service-side
-- Edge Functions continue to own all writes and privileged operations.
alter policy advertiser_profile_owner_read on public.advertiser_profiles to anon, authenticated;
alter policy advertiser_profile_owner_update on public.advertiser_profiles to anon, authenticated;
alter policy advertising_campaign_owner_read on public.advertising_campaigns to anon, authenticated;
alter policy advertising_creative_owner_read on public.advertising_creatives to anon, authenticated;
alter policy advertising_payment_owner_read on public.advertising_payments to anon, authenticated;
alter policy advertising_design_owner_read on public.advertising_design_requests to anon, authenticated;
alter policy advertising_design_payment_owner_read on public.advertising_design_payments to anon, authenticated;
alter policy advertising_refund_owner_read on public.advertising_refunds to anon, authenticated;
alter policy advertising_change_requests_select_own on public.advertising_campaign_change_requests to anon, authenticated;

-- The restrictive boundary blocks advertiser-only identities from member data,
-- but permits a dual-role identity whose Auth user has a real Match profile.
do $boundary$
declare
  rec record;
begin
  for rec in
    select schemaname, tablename
    from pg_policies
    where schemaname = 'public' and policyname = 'match_advertiser_data_boundary'
  loop
    execute format('drop policy match_advertiser_data_boundary on %I.%I', rec.schemaname, rec.tablename);
    execute format(
      'create policy match_advertiser_data_boundary on %I.%I as restrictive for all to public using ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'' or public.is_dual_member_advertiser()) with check ((current_user = ''supabase_auth_admin'') or ((select auth.jwt()->>''user_role'')) is distinct from ''advertiser'' or public.is_dual_member_advertiser())',
      rec.schemaname, rec.tablename
    );
  end loop;
end;
$boundary$;

-- Storage and Realtime boundaries follow the same dual-role rule.
do $service_boundaries$
begin
  if to_regclass('storage.objects') is not null then
    drop policy if exists match_advertiser_data_boundary on storage.objects;
    create policy match_advertiser_data_boundary on storage.objects as restrictive for all to public
      using ((current_user = 'supabase_auth_admin') or ((select auth.jwt()->>'user_role')) is distinct from 'advertiser' or public.is_dual_member_advertiser())
      with check ((current_user = 'supabase_auth_admin') or ((select auth.jwt()->>'user_role')) is distinct from 'advertiser' or public.is_dual_member_advertiser());
  end if;
  if to_regclass('realtime.messages') is not null then
    drop policy if exists match_advertiser_data_boundary on realtime.messages;
    create policy match_advertiser_data_boundary on realtime.messages as restrictive for all to public
      using ((current_user = 'supabase_auth_admin') or ((select auth.jwt()->>'user_role')) is distinct from 'advertiser' or public.is_dual_member_advertiser())
      with check ((current_user = 'supabase_auth_admin') or ((select auth.jwt()->>'user_role')) is distinct from 'advertiser' or public.is_dual_member_advertiser());
  end if;
end;
$service_boundaries$;

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

  if coalesce((select auth.jwt()->>'role'), '') = 'authenticated'
     and public.is_dual_member_advertiser() then
    return;
  end if;

  if v_path in ('advertising_campaigns','advertising_design_requests') then
    return;
  end if;

  raise sqlstate 'PGRST'
    using message = '{"code":"ADVERTISER_ACCESS_RESTRICTED","message":"Advertiser-only accounts can access advertising data only.","details":null,"hint":null}',
          detail = '{"status":403}';
end;
$guard$;
revoke all on function public.match_advertiser_api_guard() from public;
grant execute on function public.match_advertiser_api_guard() to anon, authenticated, service_role, authenticator;

commit;
