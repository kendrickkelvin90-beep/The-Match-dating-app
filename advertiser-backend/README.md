# Isolated advertiser backend

This is the implementation foundation for The Match's sponsored advertising system. It lives outside the existing `supabase/` directory so the Match member project cannot accidentally apply advertiser tables or triggers.

## Separation and safety

- Use a **separate Supabase project** for advertiser accounts and advertising data.
- Never run `database/bootstrap.sql` in the Match member project.
- Never use Match member login/signup, CAPTCHA, Google auth or member profile tables for advertiser registration.
- Never expose a service-role key, B2 key, bank account configuration or analytics HMAC secret in browser code.
- The Match member project is consulted only to verify the member's JWT and current paid entitlement in the ad-serving path.
- Sponsored creatives are private B2 objects. Only short-lived signed URLs are returned to an authorized advertiser, admin or eligible member.
- No audience targeting by sexual orientation, LGBTQ+ identity, profile answers, location history or other sensitive member data.

## Code included

- `database/bootstrap.sql`: isolated advertiser schema, RLS, campaign/payment/design/refund functions, analytics, admin controls and Auth profile trigger.
- `database/verify.sql`: privilege and RLS assertions.
- `database/test-bootstrap.sql`: disposable PostgreSQL/Auth compatibility fixture for CI only.
- `database/test-workflows.sql`: RLS, campaign payment/approval, analytics deduplication, refund and design-service lifecycle tests.
- `database/scheduler.sql`: Supabase Cron schedule for reservation expiry and scheduled campaign activation.
- `supabase/functions/advertising-api`: advertiser campaign, payment, admin, refund, metrics and design-service API.
- `supabase/functions/advertising-media-upload`: advertiser-owned private image/video creative upload and validation.
- `supabase/functions/advertising-design-upload`: admin-only private final artwork upload.
- `supabase/functions/member-ad-serving`: verifies Match member sessions, checks paid entitlements, rotates eligible campaigns and records pseudonymous events.
- `portal/..` is served from the repository root as `advertiser-portal.html`, with separate auth, campaign, payment, analytics, refund and design-service UI modules.
- `sponsored-discover-integration.js`: inserts a portrait sponsored card after every 12 organic Discover profiles, with visible-time impression tracking, CTA clicks and lazy muted video.
- `sponsored-advertising-config.js`: public feature configuration; `enabled` is deliberately `false` until setup and regression testing are complete.

## Required server-side configuration

Set these only in the separate advertiser Supabase project's Edge Function secrets:

- Standard advertiser project values: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.
- Match member verification: `MATCH_SUPABASE_URL`, `MATCH_SUPABASE_ANON_KEY`.
- Private B2: `B2_BUCKET_NAME`, `B2_S3_ENDPOINT`, `B2_REGION`, `B2_ADVERTISING_KEY_ID`, `B2_ADVERTISING_APPLICATION_KEY`. Use a separate B2 key restricted to the advertising prefix where supported.
- Bank transfer display: `ADVERTISING_BANK_NAME`, `ADVERTISING_ACCOUNT_NAME`, `ADVERTISING_ACCOUNT_NUMBER`.
- Analytics pseudonymization: `ADVERTISING_ANALYTICS_HMAC_SECRET` (long random secret).
- Portal CORS: `ADVERTISER_ALLOWED_ORIGINS` (the exact The Match origin).

The browser-only `advertiser-portal-config.js` and `sponsored-advertising-config.js` may contain only the advertiser project's URL and publishable/anon key. They must never contain service-role or B2 credentials.

## Setup order

1. Create the separate advertiser Supabase project on a plan approved by the account owner.
2. Configure advertiser email verification/recovery and Google OAuth redirect URLs in that project.
3. Apply `database/bootstrap.sql` to the advertiser project only.
4. Run `database/verify.sql`.
5. Deploy the four Edge Functions in `supabase/functions/` and set the secrets above.
6. Add the advertising admin's advertiser-project Auth user ID to `public.advertising_admins` using a trusted SQL/admin session.
7. Run `database/scheduler.sql` in that project. The campaign clock runs every minute to expire unpaid reservations and activate approved scheduled campaigns.
8. Set the public portal URL/key in `advertiser-portal-config.js`. Configure the same public values in `sponsored-advertising-config.js`, but keep `enabled: false` until all checks pass.
9. Verify private B2 upload/download, admin approval, bank confirmation, Match Plus ad-free behavior, frequency limits, analytics and the protected member flows.
10. Only after explicit approval should the feature flag be enabled, changes merged to `main`, and the production deployment released.

## Automated checks

The GitHub Actions workflow runs:
- Node syntax checks for the advertiser portal and Discover integration.
- Deno type checks for all advertiser Edge Functions.
- A disposable PostgreSQL 16 test database with RLS, campaign lifecycle, payment approval, click/impression deduplication, refund and design-service smoke tests.

These tests do not connect to or mutate either live Supabase project. Passing CI does not replace a final device/browser regression test on The Match.

## Not activated

The current branch is a work branch only. The advertiser Supabase project has not yet been provisioned or configured, no production database has been migrated, bank details and B2 credentials have not been supplied to the backend, and the Discover feature flag remains off. Do not enable the integration until those prerequisites and live-device regression checks are completed.
