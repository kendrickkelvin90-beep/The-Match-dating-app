-- Super Like redemption, inventory, notification, and mutual-like tests.
begin;
select set_config('request.jwt.claim.sub','11111111-1111-4111-8111-111111111111',true);
insert into public.coin_wallets(user_id,balance)
values('11111111-1111-4111-8111-111111111111',0)
on conflict(user_id) do nothing;
insert into public.coin_store_inventory(user_id,item_code,quantity)
values('11111111-1111-4111-8111-111111111111','super_like_1',1)
on conflict(user_id,item_code) do update set quantity=excluded.quantity;

do $$
declare v_result jsonb; v_quantity integer;
begin
  v_result := public.send_super_like(
    '22222222-2222-4222-8222-222222222222',
    'super-like-req-001'
  );
  perform public.test_assert((v_result->>'remaining')::integer=0,'one Super Like is consumed');
  perform public.test_assert((v_result->>'matched')::boolean=false,'first Super Like is not falsely matched');
  select quantity into v_quantity from public.coin_store_inventory
  where user_id='11111111-1111-4111-8111-111111111111' and item_code='super_like_1';
  perform public.test_assert(v_quantity=0,'inventory quantity decremented exactly once');
  perform public.test_assert(exists(select 1 from public.likes
    where liker_id='11111111-1111-4111-8111-111111111111'
      and liked_id='22222222-2222-4222-8222-222222222222'),'Super Like also records a normal like');
  perform public.test_assert(exists(select 1 from public.super_likes
    where sender_id='11111111-1111-4111-8111-111111111111'
      and recipient_id='22222222-2222-4222-8222-222222222222'),'Super Like event is recorded');
  perform public.test_assert(exists(select 1 from public.notifications
    where user_id='22222222-2222-4222-8222-222222222222'
      and type='like' and title='You received a Super Like'),'recipient receives a notification');

  v_result := public.send_super_like(
    '22222222-2222-4222-8222-222222222222',
    'super-like-req-001'
  );
  perform public.test_assert((v_result->>'already_processed')::boolean=true,'same request is idempotent');
  select quantity into v_quantity from public.coin_store_inventory
  where user_id='11111111-1111-4111-8111-111111111111' and item_code='super_like_1';
  perform public.test_assert(v_quantity=0,'idempotent retry does not consume another item');
end
$$;

-- Verify the larger Super Like pack is consumable and mutual likes are detected.
insert into public.likes(liker_id,liked_id)
values('11111111-1111-4111-8111-111111111111','33333333-3333-4333-8333-333333333333');
insert into public.coin_store_inventory(user_id,item_code,quantity)
values('33333333-3333-4333-8333-333333333333','super_like_5',2)
on conflict(user_id,item_code) do update set quantity=excluded.quantity;
select set_config('request.jwt.claim.sub','33333333-3333-4333-8333-333333333333',true);

do $$
declare v_result jsonb; v_quantity integer;
begin
  v_result := public.send_super_like(
    '11111111-1111-4111-8111-111111111111',
    'super-like-req-002'
  );
  perform public.test_assert((v_result->>'remaining')::integer=1,'one unit is deducted from the five-pack inventory');
  perform public.test_assert((v_result->>'matched')::boolean=true,'mutual likes are detected');
  select quantity into v_quantity from public.coin_store_inventory
  where user_id='33333333-3333-4333-8333-333333333333' and item_code='super_like_5';
  perform public.test_assert(v_quantity=1,'five-pack inventory decremented by one');
end
$$;

select set_config('request.jwt.claim.sub','44444444-4444-4444-8444-444444444444',true);
select public.test_expect_error(
  $$select public.send_super_like('22222222-2222-4222-8222-222222222222','super-like-no-stock')$$,
  'NO_SUPER_LIKES'
);
select public.test_expect_error(
  $$select public.send_super_like('44444444-4444-4444-8444-444444444444','super-like-self')$$,
  'Choose another member'
);
rollback;
