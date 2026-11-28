-- Allow dual-role Match members and advertiser-only accounts to read their own advertiser portal records.
-- Existing row-level security owner policies remain in force. No broad write access is granted.

grant select on table
  public.advertiser_profiles,
  public.advertising_campaigns,
  public.advertising_creatives,
  public.advertising_payments,
  public.advertising_design_requests,
  public.advertising_design_payments,
  public.advertising_refunds,
  public.advertising_campaign_change_requests
to anon, authenticated;

grant update on table public.advertiser_profiles to anon, authenticated;
