-- Verify gift delivery creates a DM timeline event and exactly one gift notification.
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
  v_notification_count integer;
  v_body text;
  v_dm_count integer;
  v_dm_body text;
  v_generic_count integer;
begin
  select count(*), max(body)
    into v_notification_count, v_body
  from public.notifications
  where user_id='22222222-2222-4222-8222-222222222222'
    and title='You received a gift 🎁'
    and body like '%Notification test gift gift.%';

  if v_notification_count <> 1 then
    raise exception 'Expected exactly one notification for the test gift, found %', v_notification_count;
  end if;

  if v_body not like '%2 coins are available to redeem.%' then
    raise exception 'Gift notification body did not include the redemption value: %', v_body;
  end if;

  select count(*), max(body)
    into v_dm_count, v_dm_body
  from public.messages
  where sender_id='11111111-1111-4111-8111-111111111111'
    and receiver_id='22222222-2222-4222-8222-222222222222'
    and body like '[[MATCH_GIFT:%]]';

  if v_dm_count <> 1 or v_dm_body <> (
    select '[[MATCH_GIFT:' || id::text || ']]'
    from public.member_gifts
    where sender_id='11111111-1111-4111-8111-111111111111'
      and recipient_id='22222222-2222-4222-8222-222222222222'
      and gift_code='notification_test'
  ) then
    raise exception 'Expected exactly one durable gift event in the DM, found % (%)', v_dm_count, v_dm_body;
  end if;

  select count(*) into v_generic_count
  from public.notifications
  where user_id='22222222-2222-4222-8222-222222222222'
    and title='New message';

  if v_generic_count <> 0 then
    raise exception 'Gift DM marker must not create a duplicate generic message notification.';
  end if;

  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='messages'
  ) or not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='member_gifts'
  ) then
    raise exception 'Both messages and member_gifts must be in supabase_realtime.';
  end if;
end;
$$;

rollback;
