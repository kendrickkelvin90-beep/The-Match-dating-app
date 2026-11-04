# The Match transactional membership email delivery

The existing `send-notification` Edge Function now sends a transactional email through Resend for these database notification types:

- `premium_welcome` — Premium or The Match Lite activation.
- `membership_payment_rejected` — membership payment rejection, including the admin's saved reason.

It continues to send OneSignal push notifications. The email recipient is looked up server-side from Supabase Auth using the notification's `user_id`; no email address is accepted from browser input or the webhook body.

## Sender

- From name: The Match
- From address: `noreply@beyondthebinarymedia.online`
- Resend domain: `beyondthebinarymedia.online`

The sender address must remain verified in Resend.

## Required Edge Function secrets

Add `RESEND_API_KEY` to **Supabase Dashboard → Edge Functions → Secrets** for the The Match project. The API key previously used for Supabase Auth custom SMTP is a Resend API key, but configuring Auth SMTP does not automatically expose it to Edge Functions. Reuse the existing key if it is still active; do not create or share a key in source code.

The function also requires the existing `ONESIGNAL_REST_API_KEY` for push delivery. `SUPABASE_URL` and the project secret key are supplied by Supabase's Edge Function runtime. The function supports the legacy `SUPABASE_SERVICE_ROLE_KEY` and the current `SUPABASE_SECRET_KEYS` environment variable.

Never commit API keys or service-role/secret keys to GitHub or place them in the browser app.

## Deployment checklist

1. Confirm the Resend sender domain is verified and the API key is active.
2. Add `RESEND_API_KEY` as an Edge Function secret in the correct Supabase project.
3. Deploy the updated `send-notification` function from this branch only after reviewing and testing it.
4. Confirm the existing database webhook for `public.notifications` INSERT events still points to `send-notification`.
5. Test a Premium approval, a Match Lite approval, and a rejected membership payment using a controlled test account. Confirm the email arrives at the account's registered email and the in-app notification/push still works.
6. Check Edge Function logs and Resend email logs for provider errors.

## Delivery behavior

- Email is sent only for `premium_welcome` and `membership_payment_rejected` notifications; other notification types keep their existing push-only behavior.
- Resend's `Idempotency-Key` is based on the database notification ID, preventing duplicate sends when the same webhook event is retried within Resend's idempotency window.
- A failed push or email returns an error from the webhook so the failure is visible in function logs and can be retried by the webhook delivery mechanism.
- The function does not skip transactional email merely because the member has already read the in-app notification.
- Email provider failure does not roll back the membership approval/rejection transaction. The in-app notification remains saved in the database.
- This code change alone does not deploy the Edge Function or configure project secrets. No live project settings are changed by this migration/branch update.
