-- Voice call sessions are managed only by the authenticated voice-call Edge Function.
-- The function verifies match/block status before each state transition and token issue.
drop policy if exists "Participants can update their calls" on public.call_sessions;
revoke update on table public.call_sessions from anon, authenticated;
