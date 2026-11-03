drop function if exists public.record_member_moderation(uuid,text,text,timestamptz);

create function public.record_member_moderation(
  p_user_id uuid,
  p_action text,
  p_reason text,
  p_expires_at timestamptz,
  p_actor_id uuid
)
returns jsonb
language plpgsql
set search_path = ''
as $function$
begin
  if p_actor_id is null or not exists (
    select 1 from public.app_admins where user_id = p_actor_id
  ) then
    raise exception 'Admin access denied.' using errcode = '42501';
  end if;
  if p_user_id is null or p_user_id = p_actor_id then
    raise exception 'You cannot moderate your own account.';
  end if;
  if exists (select 1 from public.app_admins where user_id = p_user_id) then
    raise exception 'Administrator accounts cannot be moderated here.';
  end if;
  if p_action not in ('suspended','banned','restored') then
    raise exception 'Invalid moderation action.';
  end if;
  if p_reason is null or char_length(btrim(p_reason)) < 3 or char_length(btrim(p_reason)) > 500 then
    raise exception 'Enter a moderation reason between 3 and 500 characters.';
  end if;
  if p_action = 'suspended' and (
    p_expires_at is null or p_expires_at <= now()
    or p_expires_at > now() + interval '30 days'
  ) then
    raise exception 'A suspension must expire within the next 30 days.';
  end if;
  if p_action in ('banned','restored') and p_expires_at is not null then
    raise exception 'This moderation action cannot have an expiry date.';
  end if;

  insert into public.member_moderation
    (user_id, status, reason, expires_at, updated_by, created_at, updated_at)
  values
    (p_user_id, p_action, btrim(p_reason), p_expires_at, p_actor_id, now(), now())
  on conflict (user_id) do update set
    status = excluded.status,
    reason = excluded.reason,
    expires_at = excluded.expires_at,
    updated_by = excluded.updated_by,
    updated_at = now();

  insert into public.member_moderation_history
    (user_id, action, reason, expires_at, actor_id)
  values
    (p_user_id, p_action, btrim(p_reason), p_expires_at, p_actor_id);

  return jsonb_build_object('success', true, 'user_id', p_user_id, 'action', p_action);
end;
$function$;

revoke all on function public.record_member_moderation(uuid,text,text,timestamptz,uuid) from public, anon, authenticated;
grant execute on function public.record_member_moderation(uuid,text,text,timestamptz,uuid) to service_role;
