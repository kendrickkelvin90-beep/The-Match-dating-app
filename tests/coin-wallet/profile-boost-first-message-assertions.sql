-- Purchased Profile Boost first-message ticket and free continuation tests.
insert into public.coin_store_inventory(user_id,item_code,quantity)
values
 ('55555555-5555-4555-8555-555555555555','profile_boost_24h',2),
 ('66666666-6666-4666-8666-666666666666','profile_boost_3',1)
on conflict(user_id,item_code) do update set quantity=excluded.quantity;

set role authenticated;
select set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
do $first_message$
declare v_result jsonb; v_message_count integer;
begin
  v_result := public.activate_my_purchased_profile_boost('profile_boost_24h');
  perform public.test_assert((v_result->>'remaining_message_tickets')::integer=1,
    'one purchased 24-hour boost grants one first-message ticket');

  v_result := public.send_discover_first_message(
    '22222222-2222-4222-8222-222222222222',
    'Hi! I liked your profile and wanted to say hello.',
    'boost-first-message-555-001'
  );
  perform public.test_assert((v_result->>'sent')::boolean=true,
    'first message is successfully sent');
  perform public.test_assert((v_result->>'remaining_tickets')::integer=0,
    'sending the first message consumes exactly one ticket');

  select count(*)::integer into v_message_count from public.messages
  where sender_id='55555555-5555-4555-8555-555555555555'
    and receiver_id='22222222-2222-4222-8222-222222222222';
  perform public.test_assert(v_message_count=1,'first message is inserted exactly once');

  v_result := public.send_discover_first_message(
    '22222222-2222-4222-8222-222222222222',
    'Hi! I liked your profile and wanted to say hello.',
    'boost-first-message-555-001'
  );
  perform public.test_assert((v_result->>'already_processed')::boolean=true,
    'retry with the same request key does not send or charge twice');
  perform public.test_assert((select count(*)=1 from public.messages
    where sender_id='55555555-5555-4555-8555-555555555555'
      and receiver_id='22222222-2222-4222-8222-222222222222'),
    'idempotent retry does not create a duplicate message');
end
$first_message$;
-- A second purchased activation adds another ticket. A failed delivery
-- (foreign-key rejection for a deleted/nonexistent target) must roll it back.
do $second_ticket$
declare v_result jsonb;
begin
  v_result := public.activate_my_purchased_profile_boost('profile_boost_24h');
  perform public.test_assert((v_result->>'remaining_message_tickets')::integer=1,
    'second purchased activation grants a second message ticket');
end
$second_ticket$;
select public.test_expect_error(
  $stmt$select public.send_discover_first_message(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    'This should fail delivery',
    'boost-first-message-555-fail'
  )$stmt$,
  'foreign key'
);
select public.test_assert(
  (select count(*)=1 from public.profile_boost_message_tickets
   where user_id='55555555-5555-4555-8555-555555555555'
     and used_at is null and expires_at > now()),
  'a failed message delivery does not consume its ticket'
);
select public.test_assert(
  (public.send_discover_first_message(
    '33333333-3333-4333-8333-333333333333',
    'A second new conversation',
    'boost-first-message-555-002'
  )->>'sent')::boolean,
  'a second purchased ticket can start a second conversation'
);
select public.test_expect_error(
  $stmt$select public.send_discover_first_message(
    '44444444-4444-4444-8444-444444444444',
    'A third new conversation without a ticket',
    'boost-first-message-555-003'
  )$stmt$,
  'NO_BOOST_MESSAGE_TICKETS'
);
select public.test_assert(
  (public.send_discover_first_message(
    '22222222-2222-4222-8222-222222222222',
    'Retry to the same person',
    'boost-first-message-555-004'
  )->>'already_sent')::boolean,
  'a second ticket is not consumed to contact the same person again'
);
reset role;

-- The recipient can reply, and the sender can continue chatting, without
-- purchasing another ticket or needing a mutual like.
set role authenticated;
select set_config('request.jwt.claim.sub','22222222-2222-4222-8222-222222222222',false);
insert into public.messages(sender_id,receiver_id,body)
values('22222222-2222-4222-8222-222222222222',
       '55555555-5555-4555-8555-555555555555',
       'Hello! Thanks for reaching out.');
reset role;

set role authenticated;
select set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
insert into public.messages(sender_id,receiver_id,body)
values('55555555-5555-4555-8555-555555555555',
       '22222222-2222-4222-8222-222222222222',
       'You are welcome!');
reset role;

select public.test_assert(
  (select count(*)=3 from public.messages
   where (sender_id='55555555-5555-4555-8555-555555555555' and receiver_id='22222222-2222-4222-8222-222222222222')
      or (sender_id='22222222-2222-4222-8222-222222222222' and receiver_id='55555555-5555-4555-8555-555555555555')),
  'both participants can continue the conversation for free after the first-message ticket is used'
);

-- A member without a mutual match or a Boost-funded conversation cannot
-- inject a message into an unrelated member's inbox.
set role authenticated;
select set_config('request.jwt.claim.sub','55555555-5555-4555-8555-555555555555',false);
select public.test_expect_error(
  $stmt$insert into public.messages(sender_id,receiver_id,body)
    values('55555555-5555-4555-8555-555555555555',
           '44444444-4444-4444-8444-444444444444',
           'Unauthorized cold message')$stmt$,
  'row-level security'
);
reset role;

-- A three-boost pack yields three separate first-message tickets when all
-- three purchased activations are activated.
set role authenticated;
select set_config('request.jwt.claim.sub','66666666-6666-4666-8666-666666666666',false);
do $three_pack$
declare v_result jsonb;
begin
  v_result := public.activate_my_purchased_profile_boost('profile_boost_3');
  perform public.test_assert((v_result->>'remaining_message_tickets')::integer=1,
    'first activation from a three-boost pack grants one ticket');
  v_result := public.activate_my_purchased_profile_boost('profile_boost_24h');
  perform public.test_assert((v_result->>'remaining_message_tickets')::integer=2,
    'second activation grants a second ticket');
  v_result := public.activate_my_purchased_profile_boost('profile_boost_24h');
  perform public.test_assert((v_result->>'remaining_message_tickets')::integer=3,
    'third activation grants a third ticket');
end
$three_pack$;
reset role;

select public.test_assert(
  (select count(*)=3 from public.profile_boost_message_tickets
   where user_id='66666666-6666-4666-8666-666666666666'
     and used_at is null and expires_at > now()),
  'three purchased boost activations retain three first-message tickets'
);
select public.test_assert(
  not has_function_privilege('anon','public.send_discover_first_message(uuid,text,text)','EXECUTE')
  and has_function_privilege('authenticated','public.send_discover_first_message(uuid,text,text)','EXECUTE'),
  'first-message RPC grants are restricted to authenticated members'
);
select 'PROFILE BOOST FIRST-MESSAGE ASSERTIONS PASSED' as result;
