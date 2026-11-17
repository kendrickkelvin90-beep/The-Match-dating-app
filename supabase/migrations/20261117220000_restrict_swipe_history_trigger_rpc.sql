-- Swipe-history recording is trigger-only, not a PostgREST RPC endpoint.
-- The trigger continues to run with its owner's privileges after this revoke.
revoke execute on function public.record_match_swipe_history()
  from public, anon, authenticated;
