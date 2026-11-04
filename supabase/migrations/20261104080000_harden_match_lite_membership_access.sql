-- Defense-in-depth for The Match Lite membership access.
drop policy if exists "Premium or Lite members can view likes they receive" on public.likes;
drop function if exists public.is_match_lite(uuid);
revoke all on table public.lite_memberships from anon, authenticated;
grant select on table public.lite_memberships to authenticated;
create policy "Premium or Lite members can view likes they receive"
  on public.likes for select to authenticated
  using (
    auth.uid() = liked_id
    and (
      public.is_match_premium(auth.uid())
      or exists (
        select 1 from public.lite_memberships lm
        where lm.user_id = auth.uid() and lm.lite_until > now()
      )
    )
  );