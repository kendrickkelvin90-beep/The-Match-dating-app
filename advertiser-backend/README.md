# The Match sponsored advertising — shared Supabase implementation

This implementation uses the existing `the-match-dating-app` Supabase project. It does not require a third project, a plan upgrade or pausing the user's other project.

## Isolation model

- Advertisers use a separate portal, advertiser profile tables, API actions and admin permissions.
- The portal uses its own browser auth storage key (`the-match-advertiser-auth`), so its local session does not overwrite the Match member app's browser session.
- Supabase Auth remains the underlying identity provider, but advertiser accounts must use a separate email from an existing dating-member account.
- The Custom Access Token Hook leaves ordinary member tokens unchanged. For an advertiser registration marked with `the_match_advertiser_registration=v1`, and only when no `public.profiles` row exists, it sets the supported JWT role to `anon` and adds the custom claim `user_role=advertiser`. It does not create or convert a Match member profile.
- The existing before-user-created hook is not modified.
- Advertiser JWTs do not receive the `authenticated` database role. The Data API pre-request guard allows only the two read-only advertiser list endpoints and the advertiser metrics RPC. All other advertiser Data API paths are rejected.
- A restrictive RLS boundary is added to every existing public table except the two read-only advertiser list tables. Matching boundaries also protect Storage objects and Realtime messages. Normal member JWTs have no `user_role=advertiser` claim, so existing member policies continue to apply.
- Advertiser direct Data API access is limited to `advertising_campaigns`, `advertising_design_requests` and `get_my_advertising_campaign_metrics`. Other advertiser reads/writes use trusted Edge Functions with ownership/admin checks.
- Ten existing member Edge Functions now reject the advertiser custom claim before performing member operations. The advertiser API, media upload and design upload functions accept only a verified `role=anon`, `user_role=advertiser` session. Member ad serving accepts only normal `role=authenticated` member sessions.
- Sponsored creatives remain private Backblaze B2 objects under the `advertising/` prefix. Use a separate B2 application key restricted to that prefix where supported.
- No targeting by sexual orientation, LGBTQ+ identity, profile answers, location history or other sensitive member data.
- Never expose service-role keys, B2 credentials, bank account configuration or the analytics HMAC secret in browser code.

## Important Auth and Data API behavior

1. The Custom Access Token Hook is global to the Match Supabase project. It must be configured under **Authentication → Hooks → Custom Access Token** with `pg-functions://postgres/public/custom_access_token_hook`.
2. The hook assigns `role=anon` and `user_role=advertiser` only to a new advertiser registration with the namespaced marker and no existing Match profile. Existing members keep their normal `authenticated` role and claims.
3. Advertisers must use a separate email from an existing dating-member account. A member with a `public.profiles` row cannot be enrolled as an advertiser.
4. The existing `before-user-created` hook remains untouched. The custom access-token hook is a separate global Auth setting and must be tested with member login, signup, CAPTCHA, Google sign-in and token refresh before activation.
5. The Data API guard is a separate PostgREST setting: `pgrst.db_pre_request`. The bootstrap creates `public.match_advertiser_api_guard()` but does not register it. Inspect `pg_db_role_setting` before using the optional `database/enable-pre-request.sql`. If another pre-request function is configured, compose the functions rather than overwriting it. The current project was inspected and no authenticator pre-request function was configured at audit time.
6. The advertiser portal uses email/password first. Google identity linking requires Supabase manual identity linking, which is a global Auth setting; review its impact on member accounts before enabling it.
7. The advertiser admin must itself use an advertiser account and be added to the server-side `advertising_admins` allowlist.

## Code included

- `database/bootstrap.sql`: shared-project advertiser tables, RLS, Auth hook, Data API guard and Storage/Realtime boundaries. It does not register the global pre-request setting.
- `database/enable-pre-request.sql`: optional, explicit activation of the Data API guard after confirming no existing pre-request hook.
- `database/disable-pre-request.sql`: rollback for that setting if it was enabled from the supplied script.
- `database/verify.sql`: verifies advertiser isolation from member tables, functions, Storage and Realtime.
- `database/test-bootstrap.sql`: disposable PostgreSQL/Auth/Storage/Realtime fixture for CI only.
- `database/test-workflows.sql`: custom Auth claim, member-data boundary, Data API pre-request, campaign, payment, analytics, refund and design-service tests.
- `database/scheduler.sql`: Supabase Cron schedule for unpaid reservation expiry and scheduled campaign activation.
- `database/campaign-change-requests.sql`: idempotent campaign change-request migration; server-side only.
- `supabase/functions/advertising-api`: advertiser campaign, payment, admin, refund, metrics and design-service API.
- `supabase/functions/advertising-media-upload`: advertiser-owned private image/video creative upload and validation.
- `supabase/functions/advertising-design-upload`: admin-only private final artwork upload.
- `supabase/functions/member-ad-serving`: verifies member JWTs, checks Match Plus entitlements, rotates eligible campaigns and records pseudonymous events in the same project.
- `../supabase/functions/*`: source snapshots of ten existing Match member Edge Functions with an advertiser-token rejection guard. Redeploy these guarded versions before enabling advertiser Auth.
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

Do not set `MATCH_SUPABASE_URL` or `MATCH_SUPABASE_ANON_KEY`; member verification and advertising data use the same Supabase project. Browser config files may contain only the existing project URL and publishable/anon key.

## Setup order — not yet performed in production

1. Review the shared-project migration and CI results.
2. Deploy the ten guarded member Edge Function versions from `supabase/functions/` before enabling advertiser Auth. Their only behavior change is to reject the advertiser custom claim; ordinary member sessions continue through the existing code.
3. Apply `database/bootstrap.sql` to the existing Match project only after explicit owner approval. Never run the old separate-project instructions.
4. Run `database/verify.sql` and Supabase security/performance advisors. Confirm the `public` schema is exposed to the Data API.
5. Inspect `pg_db_role_setting`; if no pre-request hook exists, run `database/enable-pre-request.sql`. Do not overwrite another pre-request integration.
6. Configure the Custom Access Token Hook at `pg-functions://postgres/public/custom_access_token_hook`. Test that normal member claims remain unchanged.
7. Deploy the four advertising Edge Functions to the existing project and set the server-side secrets.
8. Configure email verification/recovery redirect URLs and the advertiser admin allowlist. Review the global manual identity-linking setting before enabling Google linking.
9. Configure the private B2 advertising key, bank transfer details and analytics HMAC secret.
10. Configure the advertiser portal and Discover public URL/key, keeping `enabled: false`.
11. Test advertiser registration, email verification, sign-in, Google linking, admin approval, bank confirmation, media upload/playback, Match Plus ad-free behavior, frequency limits and all member login/signup/CAPTCHA/profile/Discover/chat/call/storage flows on Android and iOS browsers.
12. Only after explicit approval should the Discover flag be enabled and the feature launched.

## CI and launch gates

The GitHub Actions workflow runs JavaScript syntax checks, Deno type checks and disposable PostgreSQL integration tests. These tests do not connect to or mutate the live Match database. They do not replace real-device integration tests or a live advertiser/member session test.

Not yet configured or activated:
- No production advertising migration has been applied.
- No Data API pre-request setting has been enabled.
- No Auth hook has been enabled.
- No advertising or guarded member Edge Functions have been deployed.
- No B2 advertising key or HMAC secret has been configured.
- No bank details or admin allowlist have been configured.
- No live advertiser/member sessions or Android/iOS device QA have been completed.
- The sponsored advertising feature flag remains disabled.
- Nigerian advertising/privacy/legal review, including any ARCON clearance or disclosure obligations, remains a launch gate.

The previously rejected advertiser-screening checklist remains excluded. Platform-interruption extensions remain a manual operational process.
