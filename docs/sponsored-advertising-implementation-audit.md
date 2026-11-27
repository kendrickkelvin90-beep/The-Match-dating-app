# Sponsored advertising — shared-project implementation audit

**Working branch:** `work/sponsored-ads-shared-supabase-2026-11-27`  
**Audit date:** 2026-11-27  
**Status:** Shared-project adaptation in progress. Production database, Auth settings and Edge Functions remain untouched.

## Live-project inspection

- The existing Match Supabase project is active and healthy.
- Read-only inspection found 59 public base tables; all 59 currently have RLS enabled.
- The project currently has no public views or materialized views in the public schema.
- The `authenticator` database role currently has no `pgrst.db_pre_request` setting.
- The existing before-user-created Auth hook is not modified.
- The live database has no advertiser trigger on `auth.users`; the previous advertising bootstrap trigger that would have created advertiser profiles for every Auth user has been removed.
- The existing project must not be paused, deleted, upgraded or replaced to make room for advertising.

## Supabase Auth constraint and revised design

Supabase's supported Custom Access Token Hook role claim is constrained to `anon` or `authenticated`; an arbitrary Postgres role such as `advertiser` must not be assigned to the JWT `role` claim. The implementation therefore uses the supported `anon` role plus a namespaced custom claim:

- New advertiser registrations carry `the_match_advertiser_registration=v1` in user metadata.
- The Custom Access Token Hook checks that marker and confirms the Auth user has no row in `public.profiles`.
- Only then does it set `role=anon` and `user_role=advertiser`.
- Existing Match members retain their ordinary `authenticated` role and claims. Existing member profiles cannot be converted into advertiser accounts.
- The Auth hook is global but separate from the existing before-user-created hook. It has not been enabled.

## Cross-service isolation

1. **PostgREST pre-request guard:** `public.match_advertiser_api_guard()` rejects advertiser JWTs from every Data API path except `advertising_campaigns`, `advertising_design_requests` and `rpc/get_my_advertising_campaign_metrics`. The bootstrap creates the function but does not register the global `pgrst.db_pre_request` setting. An explicit optional activation script checks for an existing setting before changing it.
2. **Restrictive public-table RLS:** the bootstrap adds a restrictive policy to every public table except the two read-only advertiser list tables. For any legacy public table without RLS, the migration enables RLS with a permissive non-advertiser policy to preserve its previous access behavior while blocking advertiser claims.
3. **Storage and Realtime:** restrictive policies block advertiser claims from `storage.objects` and `realtime.messages`. Advertiser creative uploads use the private advertising B2 Edge Function, not the member Storage API.
4. **Advertiser Data API:** only read-only campaign/design request lists and the advertiser metrics RPC are directly accessible using the advertiser JWT. All other advertiser reads/writes use trusted Edge Functions with server-side ownership/admin checks.
5. **Member Edge Functions:** ten existing member Edge Function source snapshots include a signed-token claim guard that rejects `user_role=advertiser` after Auth validation: nearby reverse geocoding, B2 media upload, voice calls, B2 media access, admin moderation, view-once chat media, account deletion, B2 media migration, B2 storage cleanup and B2 media operations. Normal member JWTs are unchanged. These guarded versions have not been deployed.
7. **Advertising Edge Functions:** advertiser API/media/design upload functions require a verified `role=anon`, `user_role=advertiser` token. Member ad serving requires a normal `role=authenticated` member token and checks Match Plus entitlements.
8. **Separate browser session:** the advertiser portal uses `the-match-advertiser-auth`, so its browser session does not overwrite the Match member app session.
9. **Admin controls:** advertiser admin access is checked server-side against `advertising_admins`; the admin must use a separate advertiser account/email.

## Existing Supabase advisor baseline (read-only)

A read-only advisor run was performed before any advertising migration:

- Security: 5 existing RLS-enabled tables have no policies; 62 existing `SECURITY DEFINER` functions are executable by authenticated members. These findings pre-date the advertising migration. Some functions may be intentionally callable and require individual review; this implementation does not revoke or rewrite them because doing so could break Match features.
- Performance: existing warnings include 14 tables with multiple permissive policies and 8 unused indexes, plus row-policy auth-function evaluation notices. These are baseline findings and are not caused by the advertiser boundary.
- Health: no health lint findings were returned.
- The advertiser pre-request guard is specifically designed to prevent advertiser JWTs from reaching those existing member RPCs. It must be enabled before the advertiser Auth hook.
- Remediation references: [RLS enabled without policies](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [SECURITY DEFINER functions executable by authenticated users](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable), [multiple permissive policies](https://supabase.com/docs/guides/database/database-linter?lint=0006_multiple_permissive_policies), [unused indexes](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

## Database validation performed

- The complete shared-project advertising bootstrap was executed against the live Match database inside a transaction whose final statement was `ROLLBACK`.
- The transaction completed without SQL errors.
- A follow-up read-only query confirmed no advertiser role, advertising tables, advertiser Auth registry or Auth Hook functions persisted.
- No live roles, tables, policies, function grants, Auth settings or project configuration were changed by this test.
- The previous custom-Postgres-role and global function-ACL rewrite approach has been removed from the branch.

## Approved product configuration

- Discover-only sponsored cards labelled **Sponsored**, after every 12 organic profiles.
- Match Plus remains ad-free.
- Both static image and video creatives; portrait 4:5 presentation.
- Images: JPG, PNG, WebP up to 10 MB.
- Video: MP4 H.264, maximum 30 seconds and 20 MB; muted autoplay while visible, sound only after tap, lazy-loaded with poster.
- Packages: 7 days ₦12,000; 14 days ₦22,000; 30 days ₦40,000.
- Direct bank transfer to the existing dedicated Match business account; 24-hour reservation deadline; manual bank confirmation and separate advert approval.
- Immediate and scheduled campaigns; campaign duration begins at actual go-live.
- Concurrent eligible campaigns with fair rotation and no longer-package ranking preference.
- Exposure: one impression per member/campaign per rolling 24 hours; one unique click per member/campaign per rolling 24 hours; advertiser spacing.
- Analytics: 50% visibility for one continuous second; clicks, unique clicks and CTR; Africa/Lagos reporting; no guaranteed volume.
- No targeting by sensitive LGBTQ identity/orientation, profile answers, location history or other sensitive data; no retargeting or sale of member data.
- Design services and refund rules remain as approved in the product specification.

## Remaining setup and release gates

- Finish CI on the latest branch head and review all SQL/RLS/Auth tests.
- Deploy the ten guarded member Edge Function versions before enabling advertiser Auth.
- Apply the shared-project database migration only after explicit approval.
- Run `database/verify.sql` and Supabase security/performance/health advisors.
- Confirm the `public` schema is exposed to the Data API.
- Inspect `pg_db_role_setting` again; if no pre-request hook exists, enable `public.match_advertiser_api_guard` using the optional activation script. If another hook exists, compose it rather than overwrite it.
- Configure the Custom Access Token Hook at `pg-functions://postgres/public/custom_access_token_hook` only after member auth regression tests pass.
- Deploy advertising Edge Functions and configure the advertiser admin allowlist, email verification/recovery, Google identity linking, B2 advertising key, secrets, bank transfer details and analytics HMAC secret.
- Test real advertiser/member sessions, all member auth/onboarding/profile/Discover/Stories/Events/Nearby/chat/calls/storage flows, Match Plus ad-free behavior, campaign/payment/admin/media workflows and Android/iOS browsers.
- Complete Nigerian advertising/privacy/legal review, including applicable ARCON clearance/disclosure requirements.

The feature flag remains disabled. No production advertising migration, Data API pre-request setting, Auth hook, Edge Function deployment, bank configuration or live campaign launch has been performed. The previously rejected advertiser-screening checklist remains excluded.
