# Sponsored advertising — implementation audit and architecture gate

**Working branch:** `planning/sponsored-advertising-2026-11-27`  
**Audit date:** 2026-11-27  
**Status:** Read-only audit completed; implementation must remain isolated from production.

## Repository findings

### Application architecture
- The production app is a large, single-file `index.html` application (approximately 1.1 MB), with supporting JavaScript modules and Supabase Edge Functions.
- The repository has an existing Supabase migration history and uses database-side authorization for important member operations.
- The production branch currently contains no sponsored-advertising implementation.

### Authentication boundary
- The existing Match signup hook is configured as a Supabase Auth before-user-created hook and checks the Match deleted-account email blocklist for every signup handled by that project.
- Match member authentication, onboarding, moderation and account lifecycle are coupled to the existing Supabase project.
- A new advertiser signup system in the same Auth project would share the same Auth user namespace and signup hooks. That is not yet proven to be safely isolated from member account creation and member lifecycle triggers.
- **Architecture decision:** advertiser authentication and advertiser records must live in a separate Supabase project. Do not create advertiser accounts in the Match member Auth project. Do not change the member signup hook, member profiles, login, CAPTCHA, Google sign-in or account triggers to accommodate advertisers.

### Backblaze B2 boundary
- Existing `b2-media-upload` accepts only the categories `stories`, `chat_media`, `verification_selfies` and `event_posters`.
- It authenticates callers against the Match Supabase project and writes under the existing member-oriented B2 key structure.
- Existing `b2-media-access` authorizes reads by checking the corresponding Match database record before signing a short-lived download URL.
- **Architecture decision:** do not add sponsored creatives to the member upload/access categories or weaken their checks. Advertising needs its own advertiser-authenticated upload and media-access path, with an isolated object-key prefix and ownership checks against advertiser campaign records. B2 credentials must remain server-side. Keep ad assets private and serve short-lived signed URLs only after campaign eligibility is confirmed.

### Admin authorization
- The existing admin Edge Function authenticates the caller and checks `is_match_admin()` server-side before using a service-role client.
- Advertising admin actions must follow the same principle. No browser-supplied admin flag or client-side role is authoritative.
- The advertiser project must have a controlled advertising-admin allowlist/authorization source. It must not trust user-editable Auth metadata.

### Discover protection
- Discover eligibility and member-lane separation are enforced server-side in database functions, including `matchmaking_eligible_candidate_ids`.
- Sponsored campaigns must be selected independently of the member matchmaking candidate query. Never inject advertisers into member candidate results or profile tables.
- Discover integration must be a separately gated sponsored-card slot after 12 organic profiles, with Match Plus ad-free behavior, fair campaign rotation, repeat-exposure controls and organic fallback.
- Do not modify organic Like/Pass/Super Like actions, Stories, Events, Nearby, bottom navigation or member profile loading.

## Implementation topology

1. **Match app (existing project):** retain member auth, member data, Discover and all current monetization untouched.
2. **Advertiser Supabase project (new isolated project):** advertiser Auth, advertiser profiles, campaign records, payment records, creative metadata, reporting aggregates and admin authorization.
3. **Advertising service:** advertiser-project Edge Functions for campaign submission, payment reference generation, campaign approval, scheduling, creative authorization, serving and analytics. Secrets and B2 credentials remain server-side.
4. **B2:** private sponsored-media prefix, separate from member media categories.
5. **Advertiser portal:** standalone route/page using only the advertiser project's publishable key. It must not initialize or modify the Match member Supabase client/session.
6. **Discover ad slot:** minimal integration into the existing app, feature-flagged off by default until end-to-end testing passes.

## Approved product configuration to implement

- Discover-only sponsored cards, visibly labelled **Sponsored**.
- One slot after every 12 organic profiles.
- Match Plus members see no adverts.
- Both static image and video creatives at launch; shared portrait 4:5 card presentation.
- Image: JPG, PNG or WebP, maximum 10 MB.
- Video: MP4 (H.264; AAC audio where present), maximum 30 seconds and 20 MB; muted autoplay only while visible, sound only after a user tap, lazy-loaded and supplied with a poster.
- Packages: 7 days ₦12,000; 14 days ₦22,000; 30 days ₦40,000.
- Direct bank transfer only to the existing dedicated Match business account; no payment gateway.
- 24-hour unpaid reservation; unique campaign payment reference; manual bank transaction confirmation; receipt upload is optional evidence, not proof.
- Advert approval is separate from payment confirmation. Immediate and scheduled campaigns are supported. Duration begins at actual go-live.
- Multiple eligible campaigns may run concurrently with fair rotation. No arbitrary active-campaign cap and no longer-package ranking preference.
- Exposure safeguards: at most one impression per member/campaign per 24 hours; same advertiser separated by at least three sponsored slots.
- Analytics: impression means at least 50% visible for one continuous second; clicks and unique clicks; one unique click per member/campaign per 24 hours; CTR uses unique clicks / impressions; Africa/Lagos reporting; reporting may take several minutes to settle.
- No guaranteed impression/click volume. No sensitive LGBTQ identity/orientation targeting, retargeting or sale of member data.
- Design services: Basic ₦5,000; Premium ₦10,000; redesign/editing ₦3,000. Work starts after confirmed design payment; first design target 24–48 hours subject to workload; deadline confirmed before acceptance; two reasonable revision rounds for Basic/Premium and one for redesign/editing.
- Refund rules: free cancellation before payment; refund for paid rejected creative; no ordinary refund after campaign starts; refund duplicate payment; verified platform interruption may receive an extension. Approved refunds are processed manually to the originating payer's verified bank account, target 5–10 business days after approval, subject to applicable law.
- Advertisers may be individuals or registered businesses/organisations, with email/password and Google sign-in, verified email, and multiple campaigns per account.
- Advertiser account, payment and analytics records remain isolated from dating-member records and Match Plus/Match Lite/Match Coins.

## Required setup before end-to-end activation

The separate advertiser Supabase project does not yet exist in this repository context. Its project URL, publishable key, server-side service-role secret, Google OAuth configuration, email delivery settings and Auth redirect URLs must be provisioned before advertiser signup and campaign workflows can be tested end-to-end. Creating or upgrading a Supabase project may incur cost; do not create, upgrade or connect one without Kelvin's explicit approval.

The existing B2 bucket credentials are not to be copied into the browser or GitHub. A dedicated B2 application key scoped to the advertising prefix is preferred. Until that key and advertiser-project secrets are configured, creative upload and signed delivery remain disabled.

The actual business bank details must be entered through a protected server-side secret/configuration step. They must never be committed to the repository or embedded in public HTML/JavaScript.

## Test and release gates

Before turning on the Discover feature flag:
- Verify advertiser and member Auth sessions are independent.
- Verify advertiser users can read and change only their own advertiser profile, campaigns, payment submissions, creative metadata and aggregate reports.
- Verify only server-authorized advertising admins can approve/reject, confirm transfers, pause/resume, refund or change campaign state.
- Verify payment references are unique, unpaid reservations expire after 24 hours, duplicate transfers are detected, and client-submitted receipts never mark a campaign paid.
- Verify campaign approval and payment are both required; scheduled and immediate start boundaries use Africa/Lagos consistently; duration starts only at actual activation.
- Verify creatives enforce type, size, codec/duration and ownership checks; B2 objects remain private; no public object URLs or credentials are exposed.
- Verify rotation, one-impression-per-member/campaign/day, advertiser spacing, unique-click dedupe and CTR.
- Verify Match Plus receives no ads and unavailable inventory falls back to organic profiles.
- Verify Discover performance is not degraded by video downloads, image downloads or analytics calls.
- Run regression tests for member login/signup/CAPTCHA/Google sign-in, onboarding, Discover profile loading/actions, Stories, Events, Nearby, chat/calls, memberships, Match Coins, admin and bottom navigation.

## Release boundary

All work remains on `planning/sponsored-advertising-2026-11-27`. Do not merge to `main`, deploy, create or alter production database objects, create/upgrade external Supabase projects, or activate the Discover feature flag without Kelvin's separate explicit approval.
