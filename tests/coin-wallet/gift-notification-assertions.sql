-- Verify a committed gift creates exactly one recipient notification.
-- Use a unique test catalogue item so earlier gift assertions cannot collide.
begin;

insert into public.gift_catalog(code,name,emoji,send_cost,redeem_coins,sort_order,active)
values ('notification_test','Notification test gift','🧪',3,2,999,true)
on conflict(code) do update set name=excluded.name,send_cost=excluded.send_cost,redeem_coins=excluded.redeem_coins,active=true;

insert into public.member_gifts(
  sender_id, recipient_id, gift_code, send_cost, redeem_coins, message, request_id
) values (
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'notification_test', 3, 2, 'A test gift', gen_random_uuid()
);

do $$
declare
  v_count integer;
  v_body text;
begin
  select count(*), max(body)
    into v_count, v_body
  from public.notifications
  where user_id='22222222-2222-4222-8222-222222222222'
    and title='You received a gift 🎁'
    and body like '%Notification test gift gift.%';

  if v_count <> 1 then
    raise exception 'Expected exactly one notification for the unique test gift, found %', v_count;
  end if;

  if v_body not like '%2 coins are available to redeem.%' then
    raise exception 'Gift notification body did not include the redemption value: %', v_body;
  end if;
end;
$$;

rollback;
