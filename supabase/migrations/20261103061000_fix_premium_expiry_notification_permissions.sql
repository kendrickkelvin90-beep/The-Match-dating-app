-- Allow signed-in members to run their own Premium expiry notification check.
-- The function derives the target user exclusively from auth.uid() and does not
-- accept a user ID parameter. Keep anonymous execution explicitly revoked.

revoke all on function public.notify_expired_premium() from public;
revoke all on function public.notify_expired_premium() from anon;
grant execute on function public.notify_expired_premium() to authenticated;
