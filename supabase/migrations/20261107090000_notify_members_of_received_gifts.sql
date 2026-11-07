-- Notify the recipient whenever a new virtual gift is committed.
-- The trigger runs in the same transaction as the gift insert, so failed sends
-- cannot create notifications and idempotent retries cannot duplicate them.
create or replace function public.notify_member_gift_received()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_gift_name text;
begin
  select name into v_gift_name
  from public.gift_catalog
  where code = new.gift_code;

  insert into public.notifications (
    user_id,
    type,
    title,
    body
  ) values (
    new.recipient_id,
    'message',
    'You received a gift 🎁',
    'You received a ' || coalesce(v_gift_name, new.gift_code) ||
      ' gift. ' || new.redeem_coins::text || ' coins are available to redeem.'
  );

  return new;
end;
$$;

revoke all on function public.notify_member_gift_received() from public, anon, authenticated;

drop trigger if exists notify_member_gift_received on public.member_gifts;
create trigger notify_member_gift_received
after insert on public.member_gifts
for each row
execute function public.notify_member_gift_received();
