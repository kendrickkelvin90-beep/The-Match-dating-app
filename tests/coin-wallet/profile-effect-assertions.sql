-- Disposable PostgreSQL integration assertions for permanent animated profile effects.
insert into public.coin_store_inventory(user_id,item_code,quantity)
values('66666666-6666-4666-8666-666666666666','animated_effect',1)
on conflict(user_id,item_code) do update set quantity=excluded.quantity;

set role authenticated;
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
select public.test_assert(
  public.set_my_profile_effect('sparkle',true)='sparkle',
  'an owner could not activate an owned animated profile effect'
);
select public.test_assert(
  (select count(*)=1 from public.get_active_profile_effects(array['66666666-6666-4666-8666-666666666666'::uuid])),
  'active profile effect was not returned to the viewer'
);

select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.test_assert(
  (select count(*)=1 from public.get_active_profile_effects(array['66666666-6666-4666-8666-666666666666'::uuid])),
  'another authenticated member cannot see the active profile effect'
);

select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
do $$
begin
  begin
    perform public.set_my_profile_effect('glow',true);
    raise exception 'TEST ASSERTION FAILED: member without an effect purchase was allowed to activate one';
  exception when others then
    if sqlerrm not like '%Purchase the Animated Profile Effect%' then raise; end if;
  end;
end $$;

select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
select public.test_assert(
  public.set_my_profile_effect('hearts',true)='hearts',
  'member could not switch to a different owned profile effect'
);
select public.test_assert(
  (select count(*)=1 from public.get_active_profile_effects(array['66666666-6666-4666-8666-666666666666'::uuid])),
  'changing the active effect did not retain one active effect'
);
select public.test_assert(
  (select effect_code='hearts' from public.get_active_profile_effects(array['66666666-6666-4666-8666-666666666666'::uuid])),
  'the newly selected effect is not active'
);
select public.test_assert(
  public.set_my_profile_effect('hearts',false)='hearts',
  'member could not request effect deactivation'
);
select public.test_assert(
  (select count(*)=0 from public.get_active_profile_effects(array['66666666-6666-4666-8666-666666666666'::uuid])),
  'deactivated profile effect remains publicly active'
);
select public.test_assert(
  not has_function_privilege('anon','public.set_my_profile_effect(text,boolean)','EXECUTE')
  and has_function_privilege('authenticated','public.set_my_profile_effect(text,boolean)','EXECUTE')
  and not has_function_privilege('anon','public.get_active_profile_effects(uuid[])','EXECUTE')
  and has_function_privilege('authenticated','public.get_active_profile_effects(uuid[])','EXECUTE'),
  'profile effect RPC grants are incorrect'
);
reset role;
select 'PROFILE EFFECT ASSERTIONS PASSED' as result;
