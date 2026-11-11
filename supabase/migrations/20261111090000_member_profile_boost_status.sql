-- Let a member see only their own active Profile Boost window without
-- granting direct SELECT access to the private boost ledger.
create or replace function public.get_my_active_profile_boost()
returns table(starts_at timestamptz, ends_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $$
  select b.starts_at, b.ends_at
  from public.profile_boosts b
  where auth.uid() is not null
    and b.user_id = auth.uid()
    and b.starts_at <= now()
    and b.ends_at > now()
  order by b.ends_at desc
  limit 1;
$$;

revoke all on function public.get_my_active_profile_boost() from public, anon;
grant execute on function public.get_my_active_profile_boost() to authenticated;
