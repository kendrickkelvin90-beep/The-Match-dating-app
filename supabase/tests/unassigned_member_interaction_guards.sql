\set ON_ERROR_STOP on

do $unassigned_chat_guard$
declare
  chat_definition text;
  interaction_definition text;
  message_policy text;
  media_policy text;
  gift_definition text;
begin
  chat_definition := pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.can_chat_with_member(uuid)'::regprocedure
  ));
  interaction_definition := pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.can_interact_with_member(uuid)'::regprocedure
  ));
  gift_definition := pg_catalog.lower(pg_catalog.pg_get_functiondef(
    'public.send_member_gift(uuid,text,text,uuid)'::regprocedure
  ));

  select pg_catalog.lower(pg_catalog.pg_get_expr(polwithcheck, polrelid))
    into message_policy
  from pg_catalog.pg_policy
  where polrelid = 'public.messages'::regclass
    and polname = 'Premium members or mutual matches can send unless blocked';

  select pg_catalog.lower(pg_catalog.pg_get_expr(polwithcheck, polrelid))
    into media_policy
  from pg_catalog.pg_policy
  where polrelid = 'public.chat_media'::regclass
    and polname = 'Members send chat media to permitted conversations';

  if pg_catalog.position('public.can_interact_with_member(target_user_id)' in chat_definition) = 0 then
    raise exception 'Chat permission must include the private lane interaction guard';
  end if;

  if pg_catalog.position('from public.messages existing_message' in interaction_definition) = 0
     or pg_catalog.position('from public.likes sent_like' in interaction_definition) = 0 then
    raise exception 'Existing conversations and mutual matches must remain permitted';
  end if;

  if message_policy is null or pg_catalog.position('can_chat_with_member(receiver_id)' in message_policy) = 0 then
    raise exception 'Premium and mutual-match message inserts must use the protected chat guard';
  end if;

  if media_policy is null or pg_catalog.position('can_chat_with_member(receiver_id)' in media_policy) = 0 then
    raise exception 'Chat media inserts must use the protected chat guard';
  end if;

  if pg_catalog.position('can_chat_with_member(p_recipient_id)' in pg_catalog.lower(gift_definition)) = 0 then
    raise exception 'Gift sends must use the protected chat guard';
  end if;
end;
$unassigned_chat_guard$;

select 'unassigned chat interaction guard tests passed' as result;
