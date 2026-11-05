-- Purchased Profile Boost fulfilment tests. Runs only on the disposable CI database.
insert into public.coin_store_inventory(user_id,item_code,quantity)
values
 ('77777777-7777-4777-8777-777777777777','profile_boost_24h',1),
 ('88888888-8888-4888-8888-888888888888','profile_boost_3',1)
on conflict(user_id,item_code) do update set quantity=excluded.quantity;

set role authenticated;
select set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',false);
do $
declare v_result jsonb;
begin
  v_result := public.activate_my_purchased_profile_boost('profile_boost_24h');
  if (v_result->>'success')::boolean is distinct from true
     or (v_result->>'ends_at')::timestamptz - (v_result->>'starts_at')::timestamptz <> interval '24 hours' then
    raise exception 'TEST ASSERTION FAILED: 24-hour boost was not activated for the full duration';
  end if;
end $;
select public.test_assert(
  (select quantity=0 from public.coin_store_inventory where user_id='77777777-7777-4777-8777-777777777777' and item_code='profile_boost_24h'),
  '24-hour boost inventory was not consumed exactly once'
);
select public.test_assert(
  (select count(*)=1 from public.get_active_discover_boost_ids() where get_active_discover_boost_ids='77777777-7777-4777-8777-777777777777'::uuid),
  'activated 24-hour boost was not returned as an active Discover boost'
);

select set_config('request.jwt.claim.sub','88888888-8888-4888-8888-888888888888',false);
do $
declare v_result jsonb;
begin
  v_result := public.activate_my_purchased_profile_boost('profile_boost_3');
  if (v_result->>'success')::boolean is distinct from true
     or (v_result->>'ends_at')::timestamptz - (v_result->>'starts_at')::timestamptz <> interval '24 hours' then
    raise exception 'TEST ASSERTION FAILED: 3-boost pack did not start one 24-hour boost';
  end if;
end $;
select public.test_assert(
  (select quantity=0 from public.coin_store_inventory where user_id='88888888-8888-4888-8888-888888888888' and item_code='profile_boost_3'),
  '3-boost pack was not consumed exactly once'
);
select public.test_assert(
  (select quantity=2 from public.coin_store_inventory where user_id='88888888-8888-4888-8888-888888888888' and item_code='profile_boost_24h'),
  'unused boosts from the pack were not retained as two individual activations'
);
select public.test_assert(
  (select count(*)=1 from public.get_active_discover_boost_ids() where get_active_discover_boost_ids='88888888-8888-4888-8888-888888888888'::uuid),
  '3-boost pack did not activate a boost visible to Discover'
);

select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select public.test_expect_error(
  $$select public.activate_my_purchased_profile_boost('profile_boost_24h')$$,
  'do not have an unused 24-hour Profile Boost'
);
select public.test_assert(
  not has_function_privilege('anon','public.activate_my_purchased_profile_boost(text)','EXECUTE')
  and has_function_privilege('authenticated','public.activate_my_purchased_profile_boost(text)','EXECUTE'),
  'purchased boost RPC grants are incorrect'
);
reset role;
select 'PURCHASED PROFILE BOOST ASSERTIONS PASSED' as result;
