-- Verify a committed gift creates exactly one recipient notification.
begin;

insert into public.member_gifts(
  sender_id, recipient_id, gift_code, send_cost, redeem_coins, message, request_id
) values (
  '11111111-1111-4111-8111-111111111111',
  '22222222-2222-4222-8222-222222222222',
  'rose', 10, 8, 'A test gift', gen_random_uuid()
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
    and title='You received a gift 🎁';

  if v_count <> 1 then
    raise exception 'Expected exactly one gift notification, found %', v_count;
  end if;

  if v_body not like '%Rose gift. 8 coins are available to redeem.%' then
    raise exception 'Gift notification body did not include the gift and redemption value: %', v_body;
  end if;
end;
$$;

rollback;
