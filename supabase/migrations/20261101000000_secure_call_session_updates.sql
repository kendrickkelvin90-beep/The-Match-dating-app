-- Voice call sessions are managed only by the authenticated voice-call Edge Function.
-- The function verifies match/block status before each state transition and token issue.
-- Remove direct client writes so members cannot create forged or abusive call invitations.
drop policy if exists "Participants can update their calls" on public.call_sessions;
drop policy if exists "Users can start calls as themselves" on public.call_sessions;
revoke insert, update on table public.call_sessions from anon, authenticated;
