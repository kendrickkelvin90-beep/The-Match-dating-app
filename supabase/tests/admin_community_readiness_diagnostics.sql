\set ON_ERROR_STOP on

select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',false);
select set_config('test.is_admin','false',false);
set role authenticated;
do $non_admin$
begin
  begin
    perform * from public.get_admin_community_readiness();
    raise exception 'Non-admin unexpectedly accessed community readiness metrics';
  exception when insufficient_privilege then
    null;
  end;
end;
$non_admin$;
reset role;

select set_config('test.is_admin','true',false);
set role authenticated;
do $admin$
declare
  readiness record;
  actual_total bigint;
begin
  select * into readiness from public.get_admin_community_readiness();
  select count(*) into actual_total from public.profiles;

  if readiness.total_profiles <> actual_total then
    raise exception 'Readiness total % does not match profile total %',
      readiness.total_profiles, actual_total;
  end if;
  if readiness.lgbtq_members + readiness.straight_members
      + readiness.community_selection_needed <> readiness.total_profiles then
    raise exception 'Community readiness counts must account for every profile';
  end if;
  if readiness.fresh_nearby_locations < 0
      or readiness.legacy_members_with_fresh_location < 0 then
    raise exception 'Fresh location counts cannot be negative';
  end if;
  if readiness.legacy_members_with_fresh_location > readiness.community_selection_needed then
    raise exception 'Legacy fresh-location count cannot exceed profiles needing community choice';
  end if;
end;
$admin$;
reset role;

select 'admin community readiness diagnostics tests passed' as result;
