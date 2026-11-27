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

commit;
