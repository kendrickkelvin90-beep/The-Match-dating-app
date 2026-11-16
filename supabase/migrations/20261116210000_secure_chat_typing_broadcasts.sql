-- Restrict ephemeral typing broadcasts to the two authenticated members
-- named in the conversation topic. No message text or typing history is stored.
begin;

do $migration$
begin
  if to_regclass('realtime.messages') is null then
    raise notice 'Supabase Realtime schema is unavailable in this environment; typing-channel policies will be applied in Supabase staging/production.';
  else
    execute 'drop policy if exists "Match members can receive conversation typing" on realtime.messages';
    execute $policy$
      create policy "Match members can receive conversation typing"
      on realtime.messages
      for select
      to authenticated
      using (
        extension = 'broadcast'
        and realtime.topic() ~ '^match-typing:[0-9a-fA-F-]{36}:[0-9a-fA-F-]{36}$'
        and auth.uid()::text in (
          split_part(realtime.topic(), ':', 2),
          split_part(realtime.topic(), ':', 3)
        )
        and not exists (
          select 1
          from public.member_blocks block_record
          where (
            block_record.blocker_id::text = split_part(realtime.topic(), ':', 2)
            and block_record.blocked_id::text = split_part(realtime.topic(), ':', 3)
          ) or (
            block_record.blocker_id::text = split_part(realtime.topic(), ':', 3)
            and block_record.blocked_id::text = split_part(realtime.topic(), ':', 2)
          )
        )
      )
    $policy$;

    execute 'drop policy if exists "Match members can send their own conversation typing" on realtime.messages';
    execute $policy$
      create policy "Match members can send their own conversation typing"
      on realtime.messages
      for insert
      to authenticated
      with check (
        extension = 'broadcast'
        and payload ->> 'event' = 'typing'
        and realtime.topic() ~ '^match-typing:[0-9a-fA-F-]{36}:[0-9a-fA-F-]{36}$'
        and auth.uid()::text in (
          split_part(realtime.topic(), ':', 2),
          split_part(realtime.topic(), ':', 3)
        )
        and payload -> 'payload' ->> 'user_id' = auth.uid()::text
        and payload -> 'payload' ->> 'is_typing' in ('true','false')
        and not exists (
          select 1
          from public.member_blocks block_record
          where (
            block_record.blocker_id::text = split_part(realtime.topic(), ':', 2)
            and block_record.blocked_id::text = split_part(realtime.topic(), ':', 3)
          ) or (
            block_record.blocker_id::text = split_part(realtime.topic(), ':', 3)
            and block_record.blocked_id::text = split_part(realtime.topic(), ':', 2)
          )
        )
      )
    $policy$;
  end if;
end;
$migration$;

commit;
