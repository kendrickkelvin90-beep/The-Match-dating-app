\set ON_ERROR_STOP on

-- Seed isolated test balances and membership states.
insert into public.coin_wallets(user_id,balance) values
 ('11111111-1111-4111-8111-111111111111',1000),
 ('22222222-2222-4222-8222-222222222222',200),
 ('33333333-3333-4333-8333-333333333333',300),
 ('44444444-4444-4444-8444-444444444444',300),
 ('55555555-5555-4555-8555-555555555555',0)
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

select 'COIN WALLET AND GIFT ASSERTIONS PASSED' as result;
