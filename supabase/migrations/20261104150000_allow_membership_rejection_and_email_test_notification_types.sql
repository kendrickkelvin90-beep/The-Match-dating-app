-- Allow the new membership rejection and controlled email test notification types.
alter table public.notifications
  drop constraint if exists notifications_type_check;

alter table public.notifications
  add constraint notifications_type_check
  check (type = any (array[
    'verification_approved',
    'verification_rejected',
    'verification_reminder',
    'verification_grace_expired',
    'like',
    'message',
    'premium_welcome',
    'premium_expired',
    'story_uploaded',
    'story_limit',
    'membership_payment_rejected',
    'email_delivery_test'
  ]));
