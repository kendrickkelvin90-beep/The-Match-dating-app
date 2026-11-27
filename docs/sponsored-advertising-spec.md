# The Match Sponsored Advertising — Product Specification (Planning Draft)

**Status:** Product specification complete for owner review; implementation remains isolated to a test branch and is not approved for production  
**Prepared:** 2026-11-27  
**Working branch:** `test/sponsored-advertising-2026-11-27`  
**Production branch:** `main` (must remain unchanged during planning)

## 1. Purpose and boundaries

Add a separate sponsored-advertising product to The Match. Advertising must generate revenue without degrading the dating experience or changing existing member monetization.

This document records decisions agreed during planning. It is not permission to deploy, alter production data, or merge to `main`.

### Protected existing functionality

The eventual implementation must not disrupt or silently change:
- Member login, signup, CAPTCHA, Google sign-in, password recovery or account identity.
- Discover profile loading, card layout, Like/Pass/Super Like actions, Stories or Events.
- Nearby, chat, calls, messaging or verification.
- Existing Match Plus/Premium and Match Lite prices, payment requests, benefits or entitlements.
- Match Coins, wallet balances, coin purchases or gift flows.
- Existing bottom navigation and admin functions.

Advertiser identity and data must be separate from dating-member accounts and private member data. Do not require an advertiser to create a dating profile.

## 2. Agreed advertising product

- **Format:** Native-style sponsored cards, always clearly labelled **Sponsored**. Both image and video adverts launch from day one.
- **Display shape:** Image and video use the same portrait-style sponsored-card dimensions as the existing Discover profile-card media area. Sponsored cards must fit the existing Discover experience without resizing or redesigning organic member cards. Exact pixel/export dimensions remain to be technically specified against the current responsive card container.
- **Placement:** Discover only.
- **Frequency target:** Approximately one sponsored card after every 10–15 organic member profiles.
- **Member experience:** No top banners, intrusive pop-ups, chat ads or interruption of an active conversation.
- **Match Plus:** Completely ad-free.
- **No campaign available:** Continue showing organic profiles normally.
- **Card actions:** Advert-specific call-to-action; no Like, Pass or Super Like controls.
- **Multiple advertisers:** Multiple campaigns may run concurrently. No arbitrary fixed active-campaign cap; only eligible paid, approved campaigns enter rotation. Capacity is bounded by performance and fair-delivery controls, not by selling priority.
- **Rotation:** Fair rotation among eligible active campaigns; avoid showing the same advertiser repeatedly to one member in a short period. No preferential placement is purchased through longer package duration.
- **Advertisers:** Both individuals and registered businesses/organisations may apply.

The target frequency is one sponsored card after every 10–15 organic profiles. Use a configurable default of 12 organic profiles, with a per-member repeat cap of one campaign impression per 24 hours and a same-advertiser separation of at least three sponsored slots. If no eligible campaign exists, show organic profiles normally. These are starting safeguards and may be tuned from aggregate performance without changing the agreed moderate experience.

## 3. Advertising packages and payment

### Approved package prices

| Campaign duration | Total package price |
|---|---:|
| 7 days | ₦12,000 |
| 14 days | ₦22,000 |
| 30 days | ₦40,000 |

These are one-time package prices, not daily charges. The longer packages have a lower effective daily cost; all packages receive the same placement opportunity.

### Payment method and workflow

- Direct bank transfer only, to The Match's existing dedicated business bank account.
- No PayPal, Paystack, Flutterwave or payment-gateway integration in this phase.
- After package selection, show the package, total amount, business bank details and a unique campaign/payment reference immediately.
- Payment deadline: 24 hours after package selection. If unpaid, the pending reservation expires; the advertiser may submit a new application.
- Advertiser enters the transfer reference; receipt upload may be offered as supporting information but is not proof of payment.
- An administrator confirms the actual incoming bank transaction manually.
- Payment remains pending until manual confirmation.
- The advert must also be approved before publication.
- A scheduled campaign starts on the chosen future date only if payment and approval are complete by then.

The actual business account details must be configured securely by the owner during implementation; they are intentionally not included in this document.

## 4. Campaign timing and lifecycle

Advertisers may choose:
1. Immediate start — goes live after payment confirmation and advert approval.
2. Scheduled start — advertiser selects a future date; campaign goes live on that date if payment and approval are complete.

The 7-, 14- or 30-day duration begins when the campaign actually goes live, not when the advertiser submits the application or transfers funds.

Proposed lifecycle states for the system:
- Draft
- Awaiting payment
- Payment submitted / awaiting manual confirmation
- Paid / awaiting advert approval
- Scheduled
- Active
- Paused
- Completed
- Expired unpaid
- Rejected
- Cancelled

The final state transitions and who may trigger them must be documented in implementation design.

## 5. Advertiser application and accounts

Advertisers may register and sign in using:
- Email and password, including password recovery.
- Google sign-in.

Advertiser accounts must be separate from dating-member accounts. The implementation must not modify or reuse member login/signup flows in a way that risks breaking them.

Both individuals and businesses/organisations are accepted. Proposed application fields:
- Advertiser type (individual or business/organisation).
- Individual name or business/organisation name.
- Contact person's name where applicable.
- Contact email.
- Phone/WhatsApp contact.
- Advert headline and short description.
- Advert image/creative.
- Destination URL, if applicable.
- Selected package.
- Immediate or scheduled start and preferred start date.
- Creative-production option, if requested.

Advertisers may run multiple campaigns from one advertiser account. They may edit campaign details before submission and request changes while awaiting approval. Changes after approval or campaign launch should be handled through a documented change request so the live advert is not silently altered.

## 6. Creative submission and optional design services

Advertisers may either upload their own artwork or request optional design work from The Match.

### Approved optional service prices

| Service | Price |
|---|---:|
| Basic advert design | ₦5,000 |
| Premium advert design | ₦10,000 |
| Advert redesign/editing | ₦3,000 |

Design charges are separate from advertising package prices and are optional.

### Approved service terms

- Design work begins after the design fee is confirmed.
- First design target: within 24–48 hours after payment confirmation, depending on package and workload.
- The delivery deadline is confirmed before accepting each design request.
- Basic and Premium design: two reasonable revision rounds.
- Redesign/editing: one revision round.
- Advertiser receives the finished artwork.

Design deliverables: Basic is one clean static portrait creative using advertiser-supplied copy/assets; Premium includes a more polished custom visual direction and one primary creative; Redesign/editing updates an existing advertiser-supplied creative. Final scope is confirmed in writing before payment. Deliver final export files; editable source files are not included unless separately agreed. A revision round means one consolidated set of reasonable changes submitted together.

### Approved image and video creative rules

- Image and video creatives are both supported at launch.
- Both use the same portrait-style sponsored-card presentation.
- Video maximum duration: 30 seconds.
- Video maximum file size: 20 MB.
- Video format: MP4.
- Video playback: muted autoplay only while the advert is visible; sound is enabled only after the member taps.
- Video assets must be lazy-loaded near visibility so they do not delay organic Discover profile loading.
- Image/video campaigns use the same approved package prices and fair campaign rotation.
- Creative specification defaults: portrait 4:5 presentation, responsive to the existing Discover media container; preserve the existing organic profile-card dimensions and layout. Accept JPG, PNG and WebP images up to 10 MB; optimise and generate responsive variants server-side. Accept MP4 video up to 30 seconds and 20 MB, H.264 video with broadly compatible AAC audio where present; reject unsupported codecs and malformed files. Generate a poster thumbnail, require a preview before submission, crop with a visible focal-point preview, and never stretch creative. Video muted autoplay only while visible, sound only after member tap, and lazy-load near viewport. CTA options: Learn More, Visit Website, Contact Us, WhatsApp. WhatsApp CTA uses advertiser-provided number and opens an external WhatsApp link; website/contact actions are tracked as clicks. Validate destinations and show the final URL to the advertiser before submission.

## 7. Cancellation and refund policy

Approved policy:
- Before payment: advertiser may cancel freely.
- Paid but advert rejected: refund permitted.
- After campaign starts: no ordinary refund for unused days.
- Duplicate payment: refund the extra payment.
- Verified platform delivery interruption: The Match may offer a campaign extension for the verified lost time.

The customer-facing terms should explain how to request a permitted refund and how a verified delivery interruption is measured. Applicable law takes precedence over this policy.

## 8. Advertiser performance dashboard

The advertiser dashboard includes, at no extra charge:
- Impressions.
- Clicks.
- Click-through rate (CTR).
- Campaign status.
- Remaining campaign duration.

Advertisers may only access statistics and records belonging to their own advertiser account/campaigns.

Analytics definitions: an impression is counted when at least 50% of the sponsored card is visible for at least one continuous second; count at most one impression per member per campaign per 24 hours. A click is recorded when the member activates the advert CTA; report total clicks and unique member clicks (one unique click per member per campaign per 24 hours). CTR is impressions-based unique clicks divided by impressions. Use Africa/Lagos for displayed dates and campaign scheduling. Dashboard reporting target is near-real-time, with a clear note that counts may take several minutes to settle. Exclude known automated/preload events and server-side duplicate events; do not claim perfect bot detection. No guaranteed impression or click counts.

## 9. Admin advertising controls

Add a distinct advertising area to the existing admin dashboard. Planned controls:
- View advertiser applications and campaign records.
- Review submitted creative and campaign details.
- Approve or reject adverts.
- View payment submissions and manually confirm actual bank transfers.
- View pending, scheduled, active, paused, completed, rejected and expired campaigns.
- Schedule campaigns.
- Pause/resume campaigns.
- View campaign impressions and clicks.
- View individual advertiser records.
- View confirmed advertising revenue and payment history.

The new admin controls must use the existing server-side admin authorization pattern (including server-side verification such as `is_match_admin()`). Do not trust a client-side admin flag. Keep advertising revenue and records separate from Match Plus, Match Lite and Match Coins accounting.

## 10. Delivery and regulatory considerations

- No guaranteed impression or click count.
- If a verified platform issue interrupts delivery, consider a make-good extension for verified lost time.
- Lower-than-expected views without a platform failure do not automatically trigger a refund.
- The user wants to consider a broader ARCON arrangement later as The Match grows. However, any advertising clearance, disclosure, consumer-protection, privacy or other legal requirement that applies to a specific advert must be satisfied before publication. The product must not represent ARCON as a fraud-detection service.
- The advertiser-screening checklist previously proposed in discussion was explicitly rejected and must not be reintroduced as a product requirement. This does not waive applicable legal obligations or the already-agreed payment and advert-approval steps.

## 11. Remaining implementation-time verification (no further product questions)

The product defaults below are settled for the test implementation. Any technical or legal blocker discovered during implementation must be documented rather than silently changing an approved product decision.

- **Campaign capacity:** No arbitrary fixed campaign cap. All eligible paid and approved campaigns may be active; rotate fairly and fail open to organic profiles.
- **Permitted categories:** LGBTQ+-affirming and general lawful goods/services relevant to adult members. Exclude illegal products/services, fraudulent or deceptive offers, discriminatory/hateful content, exploitative offers, and categories prohibited by applicable law or platform policy. Do not invent an advertiser-screening checklist; the agreed payment verification and advert approval workflow remains the operational control. Any legally mandatory pre-clearance/disclosure must be observed.
- **Creative formats:** Both images and videos at launch; shared portrait 4:5 presentation. Images JPG/PNG/WebP up to 10 MB. Videos MP4/H.264 up to 30 seconds and 20 MB, with AAC audio where present, generated poster, preview/crop, muted visible-only autoplay and lazy loading.
- **CTA:** Learn More, Visit Website, Contact Us or WhatsApp.
- **Design deliverables:** Basic one clean static creative; Premium custom visual direction and one primary creative; redesign/editing of supplied artwork. Two consolidated revision rounds for Basic/Premium, one for redesign/editing. Final exports included; source/editable files only by separate agreement.
- **Advertiser access:** Separate advertiser-facing sign-in experience and advertiser identity records; email/password with recovery and Google sign-in. Require verified email before campaign submission. Do not create a dating-member profile or change member auth. Use the existing Supabase auth service only if a safe isolated identity namespace and authorization boundary can be proven; otherwise document the need for a separate auth project before implementation. No advertiser self-activation or privileged access; campaign publication still requires admin approval.
- **Edits:** Before submission, advertiser may edit freely. While pending, advertiser may withdraw and resubmit. After approval, any creative, destination, headline, package or schedule change creates a change request and pauses delivery until re-approved. No silent live edits.
- **Refund operations:** Permitted refunds are manually processed to the originating payer's verified bank account, normally within 5–10 business days after approval; duplicate transfers return only the extra payment. Record admin, amount, reason, date and reference. Applicable law overrides this operational target.
- **Analytics:** Impression requires at least 50% card visibility for one continuous second; at most one impression per member/campaign per 24 hours. Record total clicks and unique clicks, with one unique click per member/campaign per 24 hours. CTR = unique clicks / impressions. Africa/Lagos time zone; reporting may take several minutes to settle. Exclude known preload/automated and duplicate events without claiming perfect bot detection.
- **Bank details:** Configure through protected server-side secrets/admin configuration; never commit account details, secret keys or bank credentials to frontend source. Generate unguessable, unique payment references per campaign reservation.
- **Legal/regulatory:** Before accepting a category for launch, verify applicable Nigerian advertising, consumer-protection, privacy and ARCON clearance/disclosure requirements for that actual advert. Do not state that ARCON is a fraud-screening provider. Obtain qualified local review where required.

No further product questions are required to start a safe test implementation. These defaults are not a waiver of legal review.

## 12. Proposed implementation sequence (not yet authorized)

1. Treat the settled defaults in section 11 as the product baseline; record any legal or technical blocker for owner review.
2. Read-only audit of current auth, admin authorization, Discover rendering, existing payment handling, Supabase schema/RLS and deployment workflow.
3. Propose an isolated advertiser identity model and separate campaign/payment/creative tables.
4. Design least-privilege RLS and server-side functions for campaign submission, payment status, approval, scheduling, rotation and metrics.
5. Implement advertiser sign-in separately from member auth, after verifying supported Supabase OAuth configuration.
6. Implement the advertiser application, bank-transfer instructions and advertiser dashboard.
7. Implement admin campaign/payment controls.
8. Integrate sponsored cards into Discover behind a feature flag, respecting Match Plus ad-free status and current organic profile behavior.
9. Add analytics and campaign rotation with safe exposure caps.
10. Add tests for authorization isolation, payment deadline/duplicate payment, campaign state transitions, scheduling, refund cases, rotation, Match Plus ad-free behavior and regression of existing member features.
11. Run checks and create a reviewable PR. Do not merge to `main` or deploy until the owner explicitly approves after inspecting the changes.

## 13. Explicit non-goals until separately approved

- No changes to production Supabase schema or data during planning.
- No changes to member login/signup/Google sign-in/CAPTCHA.
- No changes to Match Plus, Match Lite, Match Coins or membership payment flows.
- No changes to Discover organic card layout/actions, Stories, Events, Nearby, chat, calls, verification or bottom navigation.
- No advertising implementation, merge or deployment until the complete specification is approved.


## 14. Test-branch implementation boundary

The test branch is the only permitted target for implementation work at this stage. Start with isolated advertiser tables and server-side authorization, campaign lifecycle/payment-reference primitives, upload validation and admin workflow. Keep the Discover insertion behind a disabled-by-default feature flag until end-to-end tests prove that organic card loading and actions remain unchanged. Use existing Backblaze B2 infrastructure only after confirming its current server-side upload/access contract; do not expose B2 credentials or publicise private advertiser assets. Do not change member auth routes, member tables, membership/coin flows, bottom navigation, existing Discover actions or production Supabase data. Test with synthetic advertiser accounts/campaigns and a non-production environment. Do not merge to `main`, enable the feature flag in production, run production migrations, or deploy without a separate explicit approval after review.

Required acceptance tests: advertiser/member identity isolation; advertiser can only read own campaigns and metrics; only server-authorised admins can confirm payments/approve/pause campaigns; unpaid reservations expire after 24 hours; duplicate transfer records cannot activate a campaign twice; schedule and duration boundaries use Africa/Lagos; campaign duration begins at actual activation; rejected/changed creative cannot remain live; image/video MIME/size/duration/codec validation; safe poster and lazy loading; rotation fairness and frequency caps; no sponsored cards for Match Plus; organic fallback when no campaign is eligible; impressions/clicks deduplicate correctly; no tracking before visible impression or CTA click; existing login/signup/Google/CAPTCHA, Discover Like/Pass/Super Like, Stories, Events, Nearby, chat, Match Plus, Match Lite, Coins and bottom navigation regression checks.
