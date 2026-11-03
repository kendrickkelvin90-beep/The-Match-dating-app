-- Make call invitations and call-state changes observable to both participants.
-- Keep mute state server-controlled through the authenticated voice-call Edge Function.
alter table public.call_sessions
  add column if not exists caller_muted boolean not null default false,
  add column if not exists callee_muted boolean not null default false;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'call_sessions'
  ) then
    alter publication supabase_realtime add table public.call_sessions;
  end if;
end $$;
