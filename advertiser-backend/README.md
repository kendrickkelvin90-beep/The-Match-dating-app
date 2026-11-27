# The Match sponsored advertising — shared Supabase implementation

This implementation uses the existing `the-match-dating-app` Supabase project. It does not require a third project, a Supabase plan upgrade, or pausing the user's other project.

## Isolation model

- Advertisers use a separate portal, advertiser profile tables, API actions and admin permissions.
- The portal uses a dedicated browser auth storage key (`the-match-advertiser-auth`), so its local session does not overwrite the Match member app's browser session.
- Supabase Auth remains the underlying identity provider, but advertiser accounts receive a dedicated Postgres JWT role: `advertiser`.
- The Auth Custom Access Token Hook assigns that role only when the account was explicitly registered with `the_match_advertiser_registration=v1` and has no row in `public.profiles`.
- Existing dating-member accounts are not converted into advertiser accounts. Advertisers must use a separate email address. A member JWT remains `authenticated`; an advertiser JWT is `advertiser`.
- The `advertiser` database role is not a member of `authenticated` or `anon`. It receives grants only for advertising tables and the two advertising helper/metrics functions.
- The bootstrap preserves the effective function-execution permissions of existing Match roles while removing implicit `PUBLIC` function execution. This prevents the new advertiser role from inheriting access to existing member SECURITY DEFINER functions. It also updates default function privileges so future functions are not automatically executable by PUBLIC; existing Match roles retain their previous default access.
- The Auth hook can inspect only `profiles.id` to prevent conversion of an existing member account. It cannot read profile details.
- Advertiser Edge Functions authenticate the signed JWT and require the `advertiser` role. Member ad serving accepts only `authenticated` member sessions and checks Match Plus entitlement using the existing member database.
- Sponsored creatives remain private Backblaze B2 objects under the `advertising/` prefix. Use a separate B2 application key restricted to that prefix where supported.
- No audience targeting by sexual orientation, LGBTQ+ identity, profile answers, location history or other sensitive member data.
- Never expose service-role keys, B2 credentials, bank account configuration or the analytics HMAC secret in browser code.

## Important Auth behavior

1. The Auth hook is global to the Match Supabase project. It must be enabled in **Authentication → Hooks → Custom Access Token** and point to `pg-functions://postgres/public/custom_access_token_hook`.
2. The hook leaves ordinary member tokens unchanged. Only new advertiser registrations receive the `advertiser` role.
3. A member account with an existing `public.profiles` row cannot be enrolled as an advertiser. Use a different email for advertiser registration.
4. Create advertiser accounts with email/password first. A Google identity can be linked from the advertiser workspace; Google sign-in is accepted only when the identity is already linked to an advertiser account.
5. Do not enable the hook until the shared-project migration has passed the full regression suite and the owner has approved the global Auth configuration change.

## Code included

- `database/bootstrap.sql`: shared-project advertising schema, dedicated role, function ACL isolation, Auth hook, RLS, payment/campaign/design/refund/change-request workflows and scheduler functions.
- `database/verify.sql`: checks advertiser isolation from member tables/functions and advertising RLS/grants.
- `database/test-bootstrap.sql`: disposable PostgreSQL/Auth fixture for CI only.
- `database/test-workflows.sql`: advertiser role hook, RLS, campaign payment/approval, analytics rolling 24-hour limits, change requests, refunds and design-service tests.
- `database/scheduler.sql`: Supabase Cron schedule for unpaid reservation expiry and scheduled campaign activation.
- `supabase/functions/advertising-api`: advertiser campaign, payment, admin, refund, metrics and design-service API.
- `supabase/functions/advertising-media-upload`: advertiser-owned private image/video creative upload and validation.
- `supabase/functions/advertising-design-upload`: admin-only private final artwork upload.
- `supabase/functions/member-ad-serving`: verifies member JWTs, checks Match Plus entitlements, rotates eligible campaigns and records pseudonymous events in the same project.
- `advertiser-portal.html` and supporting JS/CSS: separate advertiser workspace and browser session storage.
- `sponsored-discover-integration.js`: sponsored card after every 12 organic Discover profiles, visible-time impression tracking, CTA clicks and lazy muted video.
- `sponsored-advertising-config.js`: public config; `enabled` remains `false` until setup and live tests pass.

## Required server-side configuration

Set these only as Edge Function secrets in the existing Match Supabase project:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `B2_BUCKET_NAME`
- `B2_S3_ENDPOINT`
- `B2_REGION`
- `B2_ADVERTISING_KEY_ID`
- `B2_ADVERTISING_APPLICATION_KEY`
- `ADVERTISING_BANK_NAME`
- `ADVERTISING_ACCOUNT_NAME`
- `ADVERTISING_ACCOUNT_NUMBER`
- `ADVERTISING_ANALYTICS_HMAC_SECRET`
- `ADVERTISER_ALLOWED_ORIGINS` (exact Match origin)

Do not set `MATCH_SUPABASE_URL` or `MATCH_SUPABASE_ANON_KEY`; member verification and advertising data now use the same Supabase project. The browser config files may contain only the existing project URL and publishable/anon key.

## Setup order — not yet performed in production

1. Review the shared-project migration and CI results.
2. Confirm the Auth Custom Access Token Hook setting and exact dashboard procedure.
3. Apply `database/bootstrap.sql` to the existing Match project only after explicit owner approval. Never run the old separate-project instructions.
4. Enable `public.custom_access_token_hook` under Authentication → Hooks → Custom Access Token after migration verification.
5. Confirm the `public` schema is exposed to the Data API in the existing project, run `database/verify.sql` and Supabase security/performance advisors.
6. Deploy the four advertising Edge Functions to the existing project and set the server-side secrets.
7. Configure email verification/recovery redirect URLs and the advertiser admin allowlist. Review the global manual identity-linking setting before enabling Google linking. The advertiser admin must itself use an advertiser account and be added to the server-side allowlist.
8. Configure the private B2 advertising key, bank transfer details and analytics HMAC secret.
9. Configure the advertiser portal and Discover public URL/key, keeping `enabled: false`.
10. Test advertiser registration, email verification, sign-in, Google linking, admin approval, bank confirmation, media upload/playback, Match Plus ad-free behavior, frequency limits and all member login/signup/CAPTCHA/profile/chat flows on Android and iOS browsers.
11. Only after explicit approval should the Discover flag be enabled and the feature launched.

## CI and launch gates

The GitHub Actions workflow runs JavaScript syntax checks, Deno type checks and disposable PostgreSQL integration tests. These tests do not connect to or mutate the live Match database. They do not replace a real-device integration test.

Not yet configured or activated:
- No production advertising migration has been applied.
- No Auth hook has been enabled.
- No advertising Edge Functions have been deployed.
- No B2 advertising key or HMAC secret has been configured.
- No bank details or admin allowlist have been configured.
- No live advertiser/member sessions or Android/iOS device QA have been completed.
- The sponsored advertising feature flag remains disabled.
- Nigerian advertising/privacy/legal review, including any ARCON clearance or disclosure obligations, remains a launch gate.

The previously rejected advertiser-screening checklist remains excluded. Platform-interruption extensions remain a manual operational process.
