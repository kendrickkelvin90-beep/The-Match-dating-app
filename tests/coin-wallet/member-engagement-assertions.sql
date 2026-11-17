-- Regression coverage for member feedback and Consistency Stars.
\set ON_ERROR_STOP on

-- Exercise the 35th active day and verify one 100-coin reward.
insert into public.coin_wallets(user_id,balance)
values('11111111-1111-4111-8111-111111111111',0)
on conflict(user_id) do update set balance=0;
insert into public.member_consistency(
  user_id,current_streak_days,total_active_days,active_days_in_cycle,
  stars_progress,rewards_claimed,last_active_date
) values (
  '11111111-1111-4111-8111-111111111111',34,34,34,4,0,
  (now() at time zone 'Africa/Lagos')::date - 1
);
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',false);
select * from public.match_record_daily_activity();
select public.test_assert(
  (select balance=100 from public.coin_wallets where user_id='11111111-1111-4111-8111-111111111111'),
  '35th active day must credit exactly 100 Match Coins'
);
select public.test_assert(
  (select count(*)=1 from public.coin_ledger
   where user_id='11111111-1111-4111-8111-111111111111'
     and entry_type='consistency_reward'),
  'consistency reward must create one ledger entry'
);
select * from public.match_record_daily_activity();
select public.test_assert(
  (select balance=100 from public.coin_wallets where user_id='11111111-1111-4111-8111-111111111111'),
  'repeat check-in on the same Lagos day must not pay twice'
);

-- Verify gift entry types remain accepted by the expanded ledger constraint.
insert into public.coin_wallets(user_id,balance)
values('22222222-2222-4222-8222-222222222222',50)
on conflict(user_id) do nothing;
insert into public.coin_ledger(user_id,amount,balance_after,entry_type,idempotency_key,description)
values
 ('22222222-2222-4222-8222-222222222222',-1,49,'gift_send','test-gift-send','test'),
 ('22222222-2222-4222-8222-222222222222',1,50,'gift_redeem','test-gift-redeem','test');

-- Feedback is only prompted after seven active days, can be submitted once,
-- and cannot be submitted with an invalid rating.
insert into public.member_consistency(user_id,total_active_days)
values('33333333-3333-4333-8333-333333333333',7)
on conflict(user_id) do update set total_active_days=7;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',false);
select public.test_assert(
  (select statement_key='safety' from public.match_get_experience_prompt()),
  'first eligible feedback prompt should be safety'
);
select public.match_submit_experience_rating('safety',5);
select public.test_expect_error(
  $$select public.match_submit_experience_rating('safety',5)$$,
  'already answered'
);
select public.test_expect_error(
  $$select public.match_submit_experience_rating('respect',6)$$,
  'one to five'
);

-- A regular member cannot read another member's feedback.
set role authenticated;
select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',false);
select public.test_assert(
  (select count(*)=0 from public.member_experience_feedback),
  'non-admin must not read private feedback'
);
reset role;
select set_config('request.jwt.claim.sub','99999999-9999-4999-8999-999999999999',false);
set role authenticated;
select public.test_assert(
  (select count(*)=1 from public.member_experience_feedback),
  'admin should be able to read member feedback'
);
reset role;

select 'member engagement regression tests passed' as result;
