# Sponsored advertising — shared-project implementation audit

**Working branch:** `work/sponsored-ads-shared-supabase-2026-11-27`  
**Audit date:** 2026-11-27  
**Status:** Shared-project adaptation in progress. Production database and Auth settings remain untouched.

## Repository and live-project findings

- The Match application uses an existing Supabase project with 58 application tables, 161 recorded migrations, private schemas, existing member storage buckets and 14 active Edge Functions at the time of inspection.
- The project is active and healthy.
- Existing Match member Auth is coupled to profile creation, onboarding and account lifecycle. A before-user-created Auth hook is already configured for Match signup checks. It must not be modified or replaced.
- The live database has no trigger on `auth.users` that automatically creates a member profile. The previous advertising bootstrap did contain an Auth trigger that would have created an advertiser profile for every Auth user; that trigger has been removed from the shared-project version.
- Existing RLS policies allow authenticated members to read certain dating profile/media records. Reusing the ordinary `authenticated` role for advertisers would therefore be unsafe.
- The existing member project must not be paused, deleted, upgraded or replaced to make room for advertising.

## Shared-project security design

1. **Same Supabase project:** advertising tables and functions live in the existing Match database; no third Supabase project is required.
2. **Dedicated database role:** advertiser JWTs receive the Postgres role `advertiser`. This role is not a member of `authenticated` or `anon` and receives explicit grants only for advertising tables and the approved advertising helper/metrics functions.
3. **Custom Access Token Hook:** `private.custom_access_token_hook` assigns `role=advertiser` only when Auth metadata explicitly identifies an advertiser registration and the user has no row in `public.profiles`. Existing dating-member accounts cannot be converted to advertisers. The hook leaves normal member claims unchanged.
4. **Function ACL isolation:** the shared bootstrap snapshots effective EXECUTE access for current roles, removes implicit PUBLIC function execution, and restores the same effective privileges for existing roles. New function defaults preserve anon/authenticated/service-role access without automatically granting PUBLIC access. This prevents advertisers from inheriting existing Match SECURITY DEFINER functions.
5. **Auth hook profile check:** Supabase Auth Admin can inspect only `profiles.id`, not profile details, to prevent member accounts being enrolled as advertisers.
6. **Separate browser session:** advertiser portal uses the `the-match-advertiser-auth` storage key. Advertiser sign-out is local-only so it does not revoke the Match member app's session in another client.
7. **Advertiser API:** server functions validate the JWT signature with Supabase Auth and require the `advertiser` role. Advertiser profile creation is performed server-side; no Auth trigger is attached to `auth.users`.
8. **Member ad serving:** the Discover serving function uses the same project but accepts only `authenticated` member tokens, checks the existing Match Plus entitlements and fails closed when entitlement checks are unavailable.
9. **Google identity:** advertisers first register with email/password, then may link Google from the advertiser workspace. Google sign-in is accepted only for identities already linked to an advertiser account. A normal dating-member account is rejected by the advertiser API.
10. **B2:** sponsored creatives use a dedicated `advertising/` object prefix and a separate restricted B2 application key. Existing member upload/access functions and member storage categories remain unchanged.

## Important global Auth setting

The Custom Access Token Hook is global to the existing Match Supabase project. It is an additional hook and must coexist with the existing before-user-created hook. It must be configured only after the database migration is reviewed and all member login/signup/CAPTCHA/Google sign-in flows are tested. If the Auth hook cannot be enabled without altering the existing signup hook or breaking existing claims, stop and reassess rather than weakening the member boundary.

The hook has not been enabled. No live Auth configuration has been changed.

## Database bootstrap safety

The shared `advertiser-backend/database/bootstrap.sql` is now designed for the existing Match database. It must not be applied until:
- the full SQL passes disposable PostgreSQL integration tests;
- function ACL preservation is reviewed;
- the dedicated role and Auth hook behavior are verified;
- member-table/function isolation assertions pass;
- Supabase security/performance advisors are checked.

A read-only transaction test against the live project verified that the proposed function ACL snapshot/revoke/restore procedure produced **zero effective privilege mismatches** for existing roles. A second transaction test verified that a temporary advertiser role had zero member-table privileges and zero public/private function execution after the ACL isolation step. Both transactions were rolled back; no live grants, roles or tables were changed.

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
- Advertisers may be individuals or businesses/organisations.

## Remaining setup and release gates

- Review and run CI for the shared-project SQL, tests and Edge Functions.
- Confirm the exact Supabase Auth Hook configuration and verify coexistence with the existing before-user-created hook.
- Configure the advertiser admin allowlist, email verification/recovery and Google identity linking.
- Configure the dedicated B2 advertising key, server secrets, bank transfer details and analytics HMAC secret.
- Configure the same Match Supabase URL and publishable key in the advertiser portal and Discover config; keep sponsored ads disabled.
- Deploy advertising Edge Functions to the existing project only after approval.
- Run `database/verify.sql` and Supabase security/performance/health advisors.
- Test advertiser registration, email verification, sign-in, Google linking, admin approval, bank confirmation, private media upload/playback, analytics, Match Plus ad-free behavior and rotation.
- Test Android and iOS browsers and regression-test member login/signup/CAPTCHA/Google sign-in, onboarding, profiles, Discover, Stories, Events, Nearby, chat/calls, Match Plus, Match Coins, admin and bottom navigation.
- Complete Nigerian advertising/privacy/legal review, including applicable ARCON clearance/disclosure requirements.

The feature flag remains disabled. No production advertising migration, Auth hook activation, Edge Function deployment, bank configuration or live campaign launch has been performed. The previously rejected advertiser-screening checklist remains excluded.
