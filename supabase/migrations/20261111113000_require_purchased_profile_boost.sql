-- Profile Boosts are Coin Store purchases only.
-- Remove the legacy membership-based 30-minute activation path so older
-- clients cannot grant free boosts through the former RPC.
revoke all on function public.activate_my_profile_boost() from public, anon, authenticated;
