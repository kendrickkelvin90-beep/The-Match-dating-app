-- Preserve historical matches and conversations when a member's private
-- dating-community choice changes or is completed later.
-- New discovery remains community-separated; only an already established
-- mutual-like or message relationship bypasses the community equality check.

create or replace function public.can_interact_with_member(target_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select auth.uid() is not null
    and target_user_id is not null
    and target_user_id <> auth.uid()
    and not exists (
      select 1
      from public.member_moderation moderation
      where moderation.user_id in (auth.uid(), target_user_id)
        and (
          moderation.status = 'banned'
          or (moderation.status = 'suspended' and moderation.expires_at > now())
        )
    )
    and not exists (
      select 1
      from public.member_blocks block_record
      where (block_record.blocker_id = auth.uid() and block_record.blocked_id = target_user_id)
         or (block_record.blocker_id = target_user_id and block_record.blocked_id = auth.uid())
    )
    and (
      (
        private.member_dating_community(auth.uid()) is not null
        and private.member_dating_community(target_user_id) =
            private.member_dating_community(auth.uid())
      )
      or exists (
        select 1
        from public.likes sent_like
        join public.likes received_like
          on received_like.liker_id = sent_like.liked_id
         and received_like.liked_id = sent_like.liker_id
        where sent_like.liker_id = auth.uid()
          and sent_like.liked_id = target_user_id
      )
      or exists (
        select 1
        from public.messages existing_message
        where (existing_message.sender_id = auth.uid()
               and existing_message.receiver_id = target_user_id)
           or (existing_message.sender_id = target_user_id
               and existing_message.receiver_id = auth.uid())
      )
    );
$function$;

revoke all on function public.can_interact_with_member(uuid) from public;
revoke all on function public.can_interact_with_member(uuid) from anon;
grant execute on function public.can_interact_with_member(uuid) to authenticated;
