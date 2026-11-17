-- Trigger-only validation must not be callable as a PostgREST RPC.
-- PostgreSQL invokes the trigger using its owning function privileges; callers
-- only need table INSERT/UPDATE privileges, not EXECUTE on the trigger function.
revoke execute on function public.validate_chat_message_reply()
  from public, anon, authenticated;
