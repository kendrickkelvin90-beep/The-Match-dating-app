# The Match Sponsored Advertising — Approved Product Specification

**Status:** Approved for isolated implementation and testing only — not approved to merge, deploy or activate  
**Prepared:** 2026-11-27  
**Working branch:** `planning/sponsored-advertising-2026-11-27`  
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
- **Frequency:** One sponsored card after every 12 organic member profiles (moderate frequency).
- **Member experience:** No top banners, intrusive pop-ups, chat ads or interruption of an active conversation.
- **Match Plus:** Completely ad-free.
- **No campaign available:** Continue showing organic profiles normally.


- **Privacy:** Do not target adverts using sexual orientation, LGBTQ+ identity, profile answers, location history or other sensitive member data. Do not sell member data or introduce retargeting.
- **Card actions:** Advert-specific call-to-action; no Like, Pass or Super Like controls.
- **Multiple advertisers:** Multiple campaigns may run concurrently.
- **Rotation:** Fair rotation among all eligible paid and approved active campaigns; avoid showing the same advertiser repeatedly to one member. No preferential placement is purchased through longer package duration. No arbitrary cap on simultaneous campaigns.
- **Exposure caps:** At most one impression per member/campaign in any rolling 24-hour period; keep at least three sponsored slots between campaigns from the same advertiser where other eligible advertisers are available.
- **Advertisers:** Both individuals and registered businesses/organisations may apply.

The initial implementation uses the approved 12-profile interval and rolling 24-hour repeat-exposure cap. These may be tuned later only with a documented product decision.

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

Advertiser accounts must remain a separate account type with their own advertiser profile, portal, permissions and data. To avoid a third Supabase project, the implementation will use the existing Match Supabase Auth service with a dedicated `advertiser` Postgres JWT role and a separate browser storage key. Existing dating-member accounts cannot be converted into advertiser accounts; advertisers must use a different email. The member login/signup screens, CAPTCHA, member profile creation and member session storage must remain unchanged. A Custom Access Token Hook is a global Auth setting, so it must be reviewed, tested against the existing before-user-created hook, and enabled only after member auth regression tests pass.

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

Advertisers may run multiple campaigns from one advertiser account. Email verification is required before campaign submission. Advertisers may edit freely before submission and withdraw/resubmit while pending. Changes to approved or live campaigns require a change request and admin re-approval; pending changes never alter the live advert. Package price and duration are locked after payment.

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
- Advertiser receives the finished artwork. Editable source files are excluded unless separately agreed.
- Basic: one clean static creative using advertiser-supplied copy and assets.
- Premium: a more polished custom visual direction and one primary creative.
- Redesign/editing: update existing advertiser-supplied artwork.
- Exact scope is confirmed in writing before payment.

### Approved image and video creative rules

- Image and video creatives are both supported at launch.
- Both use the same portrait-style sponsored-card presentation.
- Video maximum duration: 30 seconds.
- Video maximum file size: 20 MB.
- Video format: MP4.
- Video playback: muted autoplay only while the advert is visible; sound is enabled only after the member taps.
- Video assets must be lazy-loaded near visibility so they do not delay organic Discover profile loading.
- Image/video campaigns use the same approved package prices and fair campaign rotation.
- Image types: JPG, PNG or WebP, maximum 10 MB.
- Video codec: H.264 in MP4; AAC audio where present. A poster thumbnail is required.
- Shared creative aspect ratio: portrait 4:5, cropped responsively without stretching.
- CTA options: Learn More, Visit Website, Contact Us or WhatsApp. Show the destination before submission and track CTA clicks.

## 7. Cancellation and refund policy

Approved policy:
- Before payment: advertiser may cancel freely.
- Paid but advert rejected: refund permitted.
- After campaign starts: no ordinary refund for unused days.
- Duplicate payment: refund the extra payment.
- Verified platform delivery interruption: The Match may offer a campaign extension for the verified lost time.

Approved refunds are handled manually to the originating payer's verified bank account, normally within 5–10 business days after approval. The customer-facing terms should explain how to request a permitted refund and how a verified delivery interruption is measured. Applicable law takes precedence over this policy.

## 8. Advertiser performance dashboard

The advertiser dashboard includes, at no extra charge:
- Impressions.
- Clicks.
- Click-through rate (CTR).
- Campaign status.
- Remaining campaign duration.

Advertisers may only access statistics and records belonging to their own advertiser account/campaigns.

- Impression: at least 50% of the sponsored card is visible continuously for one second.
- Repeat impressions: maximum one per member/campaign in any rolling 24-hour period.
- Total clicks count each tracked CTA click. Unique clicks count at most once per member/campaign in any rolling 24-hour period.
- CTR = unique clicks divided by impressions.
- Reporting timezone: Africa/Lagos. Metrics may take several minutes to settle.
- Exclude known preload, automated and duplicate events where detectable; do not claim perfect bot detection.
- Do not promise guaranteed impression or click counts.

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

The advertising tables must use a dedicated `advertiser` database role and a server-side `advertising_admins` allowlist. The Auth hook assigns the role only to explicitly registered advertiser users who do not have a dating-member profile. Do not trust a client-side admin flag or user-editable metadata for privileges. Keep advertising revenue and records separate from Match Plus, Match Lite and Match Coins accounting.

## 10. Delivery and regulatory considerations

- No guaranteed impression or click count.
- If a verified platform issue interrupts delivery, consider a make-good extension for verified lost time.
- Lower-than-expected views without a platform failure do not automatically trigger a refund.
- The user wants to consider a broader ARCON arrangement later as The Match grows. However, any advertising clearance, disclosure, consumer-protection, privacy or other legal requirement that applies to a specific advert must be satisfied before publication. The product must not represent ARCON as a fraud-detection service.
- The advertiser-screening checklist previously proposed in discussion was explicitly rejected and must not be reintroduced as a product requirement. This does not waive applicable legal obligations or the already-agreed payment and advert-approval steps.

## 11. Remaining launch gates

The product decisions above are settled. The following owner-controlled setup, legal review and live validation remain:
1. Adapt and verify the advertiser schema in the existing Match Supabase project; configure the Custom Access Token Hook, Google identity linking, email verification/recovery and redirect URLs only after regression tests pass.
2. Configure protected server-side secrets, the dedicated private B2 advertising key, the business bank details and the advertising admin allowlist.
3. Confirm applicable Nigerian advertising, consumer-protection and privacy obligations, including any ARCON clearance or disclosure requirements, with qualified local review before publication.
4. Complete real Android and iOS browser testing, including image/video playback, crop, upload, payment/admin workflows and Discover performance.
5. Verify the Match Plus ad-free entitlement and all protected member flows against the real member project before enabling the integration.

## 12. Implementation and release status

The shared-project architecture adaptation is underway on `work/sponsored-ads-shared-supabase-2026-11-27` and tracked in draft PR #339. Automated PostgreSQL/RLS, portal syntax, Edge Function type and member regression checks are being run on the branch. The feature flag remains disabled. The Auth Custom Access Token Hook, Edge Function secrets, B2 advertising key, bank details, legal review and live-device testing remain launch gates. Do not merge to `main`, deploy, apply production migrations or enable the feature until Kelvin separately approves after inspection.

## 13. Explicit production protections

- No changes to production Supabase schema or data during planning.
- No changes to member login/signup UI, CAPTCHA, member profile creation or member browser session key. The additional global Auth token hook must leave ordinary member claims unchanged and pass regression tests before activation.
- No changes to Match Plus, Match Lite, Match Coins or membership payment flows.
- No changes to Discover organic card layout/actions, Stories, Events, Nearby, chat, calls, verification or bottom navigation.
- No advertising implementation, merge or deployment until the complete specification is approved.
