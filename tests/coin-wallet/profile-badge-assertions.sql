-- Verify owner activation, public read-only visibility, and inventory enforcement.
set role authenticated;
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
select public.test_assert(public.set_my_profile_badge_active(true),'badge owner could not activate an owned badge');
select public.test_assert(
  (select count(*)=1 from public.get_active_profile_badge_ids(array['66666666-6666-4666-8666-666666666666'::uuid])),
  'activated badge is not returned by the public badge lookup'
);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.test_assert(
  (select count(*)=1 from public.get_active_profile_badge_ids(array['66666666-6666-4666-8666-666666666666'::uuid])),
  'another authenticated member cannot see an active badge'
);
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
do $$
begin
  begin
    perform public.set_my_profile_badge_active(true);
    raise exception 'TEST ASSERTION FAILED: member without a badge inventory item was allowed to activate one';
  exception when others then
    if sqlerrm not like '%need to own a Special Profile Badge%' then raise; end if;
  end;
end $$;
select public.test_assert(
  not has_function_privilege('anon','public.set_my_profile_badge_active(boolean)','EXECUTE')
  and has_function_privilege('authenticated','public.set_my_profile_badge_active(boolean)','EXECUTE')
  and not has_function_privilege('anon','public.get_active_profile_badge_ids(uuid[])','EXECUTE')
  and has_function_privilege('authenticated','public.get_active_profile_badge_ids(uuid[])','EXECUTE'),
  'profile badge RPC execution grants are incorrect'
);
reset role;
select 'PROFILE BADGE ASSERTIONS PASSED' as result;
