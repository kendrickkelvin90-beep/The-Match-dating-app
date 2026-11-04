-- Transition new Premium purchases to coin-funded Match memberships.
-- Existing approved Premium rows and expiry timestamps are deliberately untouched.

create or replace function public.match_has_advanced_filters()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select
    exists (
      select 1 from public.premium_memberships pm
      where pm.user_id = (select auth.uid())
        and pm.premium_until > now()
    )
    or public.match_plus_active_tier() in ('quarterly','annual');
$$;

revoke all on function public.match_has_advanced_filters() from public, anon;
grant execute on function public.match_has_advanced_filters() to authenticated;

-- Incoming likes are a Premium-level benefit for legacy Premium and the two
-- higher coin tiers. Match Lite retains its existing access.
drop policy if exists "Premium or Lite members can view likes they receive" on public.likes;
create policy "Premium Lite or higher coin tiers can view received likes"
on public.likes
for select
to authenticated
using (
  auth.uid() = liked_id
  and (
    public.is_match_premium(auth.uid())
    or exists (
      select 1 from public.lite_memberships lm
      where lm.user_id = auth.uid() and lm.lite_until > now()
    )
    or public.match_plus_active_tier() in ('quarterly','annual')
  )
);

-- Stop new cash-funded Premium weekly/monthly/yearly requests.
-- The Lite offer remains available through its existing ₦1,000 payment flow.
-- Admins can still review any legacy requests already submitted.
drop policy if exists "Members can submit their own pending premium payment request" on public.premium_payment_requests;
create policy "Members can submit their own pending Lite payment request"
on public.premium_payment_requests
for insert
to authenticated
with check (
  (select auth.uid()) = user_id
  and status = 'pending'
  and plan = 'lite_monthly'
);
