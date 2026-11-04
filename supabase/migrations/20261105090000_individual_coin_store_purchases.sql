-- Allow members to purchase the four currently advertised individual like items.
-- Spending remains server-side; raw coin_spend is never exposed to authenticated clients.
create or replace function public.coin_buy_store_item(
  p_item_code text,
  p_idempotency_key text
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Sign in to continue';
  end if;
  if p_item_code not in ('super_like_1','super_like_5','extra_likes_10','extra_likes_30','profile_boost_24h','profile_boost_3','priority_7d','priority_30d','decorative_badge','animated_effect') then
    raise exception 'This store item is not available for purchase';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 120 then
    raise exception 'A valid purchase reference is required';
  end if;
  -- coin_spend locks the wallet, validates the full item/price against its
  -- ledger, and atomically records both the debit and inventory quantity.
  return public.coin_spend(p_item_code,1,p_idempotency_key);
end;
$$;

revoke all on function public.coin_buy_store_item(text,text) from public, anon;
grant execute on function public.coin_buy_store_item(text,text) to authenticated;
