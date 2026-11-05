\set ON_ERROR_STOP on

-- Seed isolated test balances and membership states.
insert into public.coin_wallets(user_id,balance) values
 ('11111111-1111-4111-8111-111111111111',1000),
 ('22222222-2222-4222-8222-222222222222',200),
 ('33333333-3333-4333-8333-333333333333',300),
 ('44444444-4444-4444-8444-444444444444',300),
 ('55555555-5555-4555-8555-555555555555',0),
 ('66666666-6666-4666-8666-666666666666',2000)
on conflict(user_id) do update set balance=excluded.balance;

insert into public.match_plus_memberships(user_id,tier,started_at,expires_at) values
 ('33333333-3333-4333-8333-333333333333','plus',now()-interval '20 days',now()+interval '10 days'),
 ('44444444-4444-4444-8444-444444444444','annual',now()-interval '40 days',now()-interval '2 days')
on conflict(user_id) do update set tier=excluded.tier,started_at=excluded.started_at,expires_at=excluded.expires_at;

-- Step 1: same membership request key must charge and extend exactly once.
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.coin_buy_membership('plus','membership:plus:duplicate-0001');
select public.coin_buy_membership('plus','membership:plus:duplicate-0001');
select public.test_assert((select balance=700 from public.coin_wallets where user_id='11111111-1111-4111-8111-111111111111'),'same-key membership retry deducted more than once');
select public.test_assert((select count(*)=1 from public.coin_ledger where user_id='11111111-1111-4111-8111-111111111111' and idempotency_key='membership:plus:duplicate-0001'),'same-key membership retry created multiple ledger rows');
select public.test_expect_error(
  $cmd$select public.coin_buy_membership('annual','membership:plus:duplicate-0001')$cmd$,
  'already used for a different membership transaction'
);

-- Step 2: insufficient balance must leave wallet and ledger untouched.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.test_expect_error(
  $cmd$select public.coin_buy_membership('plus','membership:plus:insufficient-0001')$cmd$,
  'Not enough coins'
);
select public.test_assert((select balance=200 from public.coin_wallets where user_id='22222222-2222-4222-8222-222222222222'),'insufficient-balance request changed wallet');
select public.test_assert((select count(*)=0 from public.coin_ledger where user_id='22222222-2222-4222-8222-222222222222'),'insufficient-balance request wrote ledger');

-- Step 3: active membership expiry extends from the existing expiry.
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
do $test$
declare v_before timestamptz; v_after timestamptz;
begin
  select expires_at into v_before from public.match_plus_memberships where user_id=auth.uid();
  perform public.coin_buy_membership('plus','membership:plus:active-expiry-0001');
  select expires_at into v_after from public.match_plus_memberships where user_id=auth.uid();
  if v_after < v_before+interval '29 days' or v_after > v_before+interval '31 days' then
    raise exception 'TEST ASSERTION FAILED: active expiry did not extend by 30 days';
  end if;
end
$test$;

-- Step 4: expired membership restarts from now.
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
do $test$
declare v_after timestamptz; v_started timestamptz;
begin
  perform public.coin_buy_membership('plus','membership:plus:expired-restart-0001');
  select expires_at,started_at into v_after,v_started from public.match_plus_memberships where user_id=auth.uid();
  if v_after < now()+interval '29 days' or v_after > now()+interval '31 days' or v_started < now()-interval '1 minute' then
    raise exception 'TEST ASSERTION FAILED: expired membership did not restart from now';
  end if;
end
$test$;

-- Step 5: admin transfer approval is atomic and cannot credit twice.
select set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
do $purchase$
declare v_request uuid;
begin
  v_request:=public.coin_submit_purchase('starter_50','Test Sender','REF-COIN-TEST-001');
  perform set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',false);
  perform public.coin_admin_review_purchase(v_request,'approved',null);
  perform public.test_expect_error(
    format('select public.coin_admin_review_purchase(%L,''approved'',null)',v_request),
    'already been reviewed'
  );
end
$purchase$;
select public.test_assert((select balance=50 from public.coin_wallets where user_id='55555555-5555-4555-8555-555555555555'),'admin approval did not credit exactly 50 coins');
select public.test_assert((select count(*)=1 from public.coin_ledger where user_id='55555555-5555-4555-8555-555555555555' and entry_type='purchase_credit'),'admin approval duplicated ledger credit');
select public.test_assert((select count(*)=1 from public.notifications where user_id='55555555-5555-4555-8555-555555555555' and type='coins_credited'),'admin approval notification count is incorrect');

-- Step 6: gift send retry returns the same gift and charges once.
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.send_member_gift(
 '22222222-2222-4222-8222-222222222222','rose','A little gift',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);
select public.send_member_gift(
 '22222222-2222-4222-8222-222222222222','rose','A little gift',
 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
);
select public.test_assert((select balance=690 from public.coin_wallets where user_id='11111111-1111-4111-8111-111111111111'),'gift retry deducted sender twice');
select public.test_assert((select count(*)=1 from public.member_gifts where sender_id='11111111-1111-4111-8111-111111111111' and request_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),'gift retry created multiple gifts');
select public.test_expect_error(
 $cmd$select public.send_member_gift('33333333-3333-4333-8333-333333333333','star',null,'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb')$cmd$,
 'already used for a different gift'
);

-- Step 7: recipient can redeem once; duplicate redemption cannot credit twice.
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
do $redeem$
declare v_gift uuid;
begin
  select id into v_gift from public.member_gifts where request_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb';
  perform public.redeem_member_gift(v_gift);
  perform public.test_expect_error(
    format('select public.redeem_member_gift(%L)',v_gift),
    'already been redeemed'
  );
end
$redeem$;
select public.test_assert((select balance=208 from public.coin_wallets where user_id='22222222-2222-4222-8222-222222222222'),'gift redemption did not credit exactly 8 coins');
select public.test_assert((select count(*)=1 from public.coin_ledger where user_id='22222222-2222-4222-8222-222222222222' and entry_type='gift_redeem'),'gift redemption duplicated ledger credit');

-- Step 8: admin gift catalogue writes are server-authorized.
select set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',false);
select public.admin_save_gift('test_gift','Test Gift','🎁',15,12,99);
select public.admin_set_gift_active('test_gift',false);
select public.test_assert((select active=false from public.gift_catalog where code='test_gift'),'admin gift activation toggle failed');
select public.test_assert((select count(*)>=1 from public.admin_gift_activity(10)),'admin gift activity returned no rows');

-- Step 9: authenticated clients cannot invoke the raw spending primitive.
select public.test_assert(not has_function_privilege('authenticated','public.coin_spend(text,integer,text)','EXECUTE'),'authenticated role can execute coin_spend directly');
select public.test_assert(has_function_privilege('authenticated','public.coin_buy_membership(text,text)','EXECUTE'),'authenticated role cannot execute coin_buy_membership');


-- Step 10: individual store purchases debit once and credit the matching inventory.
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.coin_buy_store_item('super_like_5','store:super-like-5:test-0001');
select public.coin_buy_store_item('super_like_5','store:super-like-5:test-0001');
select public.test_assert((select balance=645 from public.coin_wallets where user_id='11111111-1111-4111-8111-111111111111'),'super-like retry charged more than once');
select public.test_assert((select quantity=1 from public.coin_store_inventory where user_id='11111111-1111-4111-8111-111111111111' and item_code='super_like_5'),'five Super Likes were not added to inventory');
select public.test_assert((select count(*)=1 from public.coin_store_purchases where user_id='11111111-1111-4111-8111-111111111111' and item_code='super_like_5'),'super-like retry created multiple purchase records');
select public.coin_buy_store_item('extra_likes_10','store:extra-likes-10:test-0001');
select public.test_assert((select balance=615 from public.coin_wallets where user_id='11111111-1111-4111-8111-111111111111'),'Extra Likes purchase did not deduct 30 coins');
select public.test_assert((select quantity=1 from public.coin_store_inventory where user_id='11111111-1111-4111-8111-111111111111' and item_code='extra_likes_10'),'ten Extra Likes were not added to inventory');
select set_config('request.jwt.claim.sub','77777777-7777-4777-8777-777777777777',false);
select public.test_expect_error(
  $cmd$select public.coin_buy_store_item('extra_likes_30','store:extra-likes-30:insufficient')$cmd$,
  'Not enough coins'
);
select public.test_assert((select balance=615 from public.coin_wallets where user_id='11111111-1111-4111-8111-111111111111'),'store purchase test wallet balance changed unexpectedly');
select public.test_expect_error(
  $cmd$select public.coin_buy_store_item('profile_boost_24h','store:unsupported:item-0001')$cmd$,
  'not available for purchase'
);
select public.test_assert(
  has_function_privilege('authenticated','public.coin_buy_store_item(text,text)','EXECUTE')
  and not has_function_privilege('anon','public.coin_buy_store_item(text,text)','EXECUTE'),
  'store purchase RPC grants are incorrect'
);


-- Step 10b: every remaining advertised store product can be bought individually.
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
select public.coin_buy_store_item('profile_boost_24h','store:boost24:test-0001');
select public.coin_buy_store_item('profile_boost_3','store:boost3:test-0001');
select public.coin_buy_store_item('priority_7d','store:priority7:test-0001');
select public.coin_buy_store_item('priority_30d','store:priority30:test-0001');
select public.coin_buy_store_item('decorative_badge','store:badge:test-0001');
select public.coin_buy_store_item('animated_effect','store:effect:test-0001');
select public.test_assert((select balance=1260 from public.coin_wallets where user_id='66666666-6666-4666-8666-666666666666'),'remaining store purchases deducted an incorrect amount');
select public.test_assert((select count(*)=6 from public.coin_store_purchases where user_id='66666666-6666-4666-8666-666666666666'),'not all remaining store products created purchase records');
select public.test_assert((select quantity=1 from public.coin_store_inventory where user_id='66666666-6666-4666-8666-666666666666' and item_code='profile_boost_24h'),'24-hour boost credit missing');
select public.test_assert((select quantity=1 from public.coin_store_inventory where user_id='66666666-6666-4666-8666-666666666666' and item_code='profile_boost_3'),'three-boost pack missing');
select public.test_assert((select quantity=1 from public.coin_store_inventory where user_id='66666666-6666-4666-8666-666666666666' and item_code='priority_7d'),'seven-day priority item missing');
select public.test_assert((select quantity=1 from public.coin_store_inventory where user_id='66666666-6666-4666-8666-666666666666' and item_code='priority_30d'),'30-day priority item missing');
select public.test_assert((select quantity=1 from public.coin_store_inventory where user_id='66666666-6666-4666-8666-666666666666' and item_code='decorative_badge'),'special badge item missing');
select public.test_assert((select quantity=1 from public.coin_store_inventory where user_id='66666666-6666-4666-8666-666666666666' and item_code='animated_effect'),'animated effect item missing');

-- Step 11: exercise the actual gift RLS policies as authenticated members.
-- The disposable database uses auth.uid() backed by the same JWT-sub setting
-- Supabase exposes to Postgres, but does not use any production credentials.
set role authenticated;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select public.test_assert(
  (select count(*)=1 from public.member_gifts where request_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  'sender cannot read their own sent gift'
);
select public.test_assert(
  (select count(*)=1 from public.member_gifts where recipient_id='22222222-2222-4222-8222-222222222222' and sender_id='11111111-1111-4111-8111-111111111111'),
  'sender cannot read the gift they sent to the recipient'
);
select public.test_assert(
  (select count(*)=1 from public.gift_catalog where code='rose'),
  'authenticated member cannot read active gift catalogue'
);
select public.test_assert(
  (select count(*)=0 from public.gift_catalog where code='test_gift'),
  'non-admin can read an inactive catalogue entry without participating in it'
);
select public.test_assert(
  not has_table_privilege('authenticated','public.member_gifts','INSERT')
  and not has_table_privilege('authenticated','public.member_gifts','UPDATE')
  and not has_table_privilege('authenticated','public.member_gifts','DELETE')
  and not has_table_privilege('authenticated','public.gift_catalog','INSERT')
  and not has_table_privilege('authenticated','public.gift_catalog','UPDATE')
  and not has_table_privilege('authenticated','public.gift_catalog','DELETE'),
  'authenticated role has direct write privileges on gift tables'
);
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
select public.test_assert(
  (select count(*)=1 from public.member_gifts where request_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  'recipient cannot read their received gift'
);
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select public.test_assert(
  (select count(*)=0 from public.member_gifts where request_id='bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'),
  'unrelated member can read another pair of members gift'
);
select public.test_assert(
  not has_function_privilege('anon','public.send_member_gift(uuid,text,text,uuid)','EXECUTE')
  and has_function_privilege('authenticated','public.send_member_gift(uuid,text,text,uuid)','EXECUTE')
  and not has_function_privilege('anon','public.redeem_member_gift(uuid)','EXECUTE')
  and has_function_privilege('authenticated','public.redeem_member_gift(uuid)','EXECUTE'),
  'gift RPC execution grants are incorrect'
);
select set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',false);
select public.test_assert(
  (select count(*)=1 from public.gift_catalog where code='test_gift'),
  'admin cannot read inactive catalogue entries'
);
select public.test_assert(
  (select count(*)=1 from public.admin_gift_activity(10) where gift_id is not null),
  'admin activity RPC is not available to an authorized admin'
);
reset role;

select 'COIN WALLET AND GIFT ASSERTIONS PASSED' as result;
