-- Update The Match Lite 30-day membership price to NGN 2,000.
-- Existing Premium plan prices and membership entitlements are unchanged.
alter table public.premium_payment_requests
  drop constraint if exists premium_payment_plan_amount_check;

alter table public.premium_payment_requests
  add constraint premium_payment_plan_amount_check
  check (
    (plan = 'weekly' and amount_ngn = 4000)
    or (plan = 'monthly' and amount_ngn = any(array[3000,5000,8000]::integer[]))
    or (plan = 'yearly' and amount_ngn = any(array[20000,49800,50000]::integer[]))
    or (plan = 'lite_monthly' and amount_ngn = 2000)
  );
