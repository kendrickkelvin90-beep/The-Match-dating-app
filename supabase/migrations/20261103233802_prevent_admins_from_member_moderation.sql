create or replace function public.record_member_moderation(
  p_user_id uuid,
  p_action text,
  p_reason text,
  p_expires_at timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor uuid := (select auth.uid());
begin
  if actor is null or not public.is_match_admin() then
    raise exception 'Admin access denied.' using errcode = '42501';
  end if;
  if p_user_id is null or p_user_id = actor then
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
    (p_user_id, p_action, btrim(p_reason), p_expires_at, actor, now(), now())
  on conflict (user_id) do update set
    status = excluded.status,
    reason = excluded.reason,
    expires_at = excluded.expires_at,
    updated_by = excluded.updated_by,
    updated_at = now();

  insert into public.member_moderation_history
    (user_id, action, reason, expires_at, actor_id)
  values
    (p_user_id, p_action, btrim(p_reason), p_expires_at, actor);

  return jsonb_build_object('success', true, 'user_id', p_user_id, 'action', p_action);
end;
$function$;
