-- Prevent unassigned or cross-lane members from starting new conversations.
-- Existing mutual matches and conversations remain available.
begin;

create or replace function public.can_chat_with_member(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select auth.uid() is not null
    and target_user_id is not null
    and target_user_id <> auth.uid()
    and not exists (
      select 1
      from public.member_moderation m
      where m.user_id in (auth.uid(), target_user_id)
        and (
          m.status = 'banned'
          or (m.status = 'suspended' and m.expires_at > pg_catalog.now())
        )
    )
    and not exists (
      select 1
      from public.member_blocks b
      where (b.blocker_id = auth.uid() and b.blocked_id = target_user_id)
         or (b.blocker_id = target_user_id and b.blocked_id = auth.uid())
    )
    and public.can_interact_with_member(target_user_id) is true;
$function$;

comment on function public.can_chat_with_member(uuid) is
  'Allows chat only within the same private orientation-derived dating lane, while preserving established mutual matches and existing conversations. Blocks and moderation restrictions remain enforced.';

commit;
