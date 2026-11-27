-- Keep chat push previews faithful to the message that was actually sent.
-- The send-notification Edge Function already maps notification.title to the
-- push heading and notification.body to the push preview, so store the sender
-- name and message body here rather than a generic "sent you a message" string.

create or replace function public.notify_match_message()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_name text;
begin
  -- Gift notifications are sent by notify_member_gift_received().
  -- Do not create a second generic notification for the DM delivery marker.
  if left(new.body, 13) = '[[MATCH_GIFT:' and right(new.body, 2) = ']]' and length(new.body) = 51 then
    return new;
  end if;

  if new.sender_id = new.receiver_id then
    return new;
  end if;

  select nullif(btrim(display_name), '')
    into v_name
  from public.profiles
  where id = new.sender_id;

  insert into public.notifications (
    user_id,
    type,
    title,
    body,
    related_user_id
  )
  values (
    new.receiver_id,
    'message',
    coalesce(v_name, 'A member'),
    left(new.body, 500),
    new.sender_id
  );

  return new;
end;
$function$;
