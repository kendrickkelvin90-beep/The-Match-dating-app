-- Permit an advertiser-owned campaign to be soft-deleted while preserving payment and audit records.
-- The member ad-serving function only selects active/scheduled campaigns, so this status immediately stops delivery.
alter table public.advertising_campaigns
  drop constraint if exists advertising_campaigns_status_check;

alter table public.advertising_campaigns
  add constraint advertising_campaigns_status_check
  check (status in (
    'draft','awaiting_payment','payment_review','awaiting_approval','scheduled',
    'active','paused','completed','expired_unpaid','rejected','cancelled','deleted'
  ));
