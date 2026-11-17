-- Secure View Once media delivery.
-- The receiver must claim the media atomically; the Edge Function signs the
-- private object before the claim and returns the URL only to the winning claim.

create or replace function public.claim_view_once_chat_media(p_media_id uuid)
returns table(storage_path text, media_type text, view_once boolean)
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_media public.chat_media%rowtype;
  v_other_user uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_media
  from public.chat_media
  where id = p_media_id
    and (sender_id = auth.uid() or receiver_id = auth.uid())
  for update;

  if not found then
    raise exception 'Media not found or access denied';
  end if;

  v_other_user := case
    when v_media.sender_id = auth.uid() then v_media.receiver_id
    else v_media.sender_id
  end;

  if public.can_interact_with_member(v_other_user) is distinct from true then
    raise exception 'This conversation is unavailable';
  end if;

  -- Keep the same paid-or-mutual-match gate used by the chat-media SELECT policy.
  if not (
    public.is_match_premium(v_media.sender_id)
    or public.are_users_mutual_matches(v_media.sender_id, v_media.receiver_id)
  ) then
    raise exception 'Chat media access is unavailable';
  end if;

  if v_media.view_once and v_media.receiver_id = auth.uid() then
    if v_media.opened_at is not null then
      raise exception 'This View Once media has already been opened';
    end if;

    update public.chat_media
       set opened_at = now()
     where id = v_media.id
       and opened_at is null;

    if not found then
      raise exception 'This View Once media has already been opened';
    end if;
  elsif v_media.view_once and v_media.sender_id = auth.uid() then
    -- Sender previews remain available; they do not consume the receiver's view.
    null;
  end if;

  return query select v_media.storage_path, v_media.media_type, v_media.view_once;
end;
$function$;

revoke all on function public.claim_view_once_chat_media(uuid) from public, anon;
grant execute on function public.claim_view_once_chat_media(uuid) to authenticated;
