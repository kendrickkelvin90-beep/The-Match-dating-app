# The Match Sponsored Advertising — Product Specification (Planning Draft)

**Status:** Planning draft only — not approved for implementation  
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
- **Frequency target:** Approximately one sponsored card after every 10–15 organic member profiles.
- **Member experience:** No top banners, intrusive pop-ups, chat ads or interruption of an active conversation.
- **Match Plus:** Completely ad-free.
- **No campaign available:** Continue showing organic profiles normally.
- **Card actions:** Advert-specific call-to-action; no Like, Pass or Super Like controls.
- **Multiple advertisers:** Multiple campaigns may run concurrently.
- **Rotation:** Fair rotation among eligible active campaigns; avoid showing the same advertiser repeatedly to one member in a short period. No preferential placement is purchased through longer package duration.
- **Advertisers:** Both individuals and registered businesses/organisations may apply.

The exact frequency and repeat-exposure window will be configurable and should be validated against real usage before launch.

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

Exact design deliverables, file dimensions, formats, source-file inclusion and the definition of a revision round remain to be specified.

### Approved image and video creative rules

- Image and video creatives are both supported at launch.
- Both use the same portrait-style sponsored-card presentation.
- Video maximum duration: 30 seconds.
- Video maximum file size: 20 MB.
- Video format: MP4.
- Video playback: muted autoplay only while the advert is visible; sound is enabled only after the member taps.
- Video assets must be lazy-loaded near visibility so they do not delay organic Discover profile loading.
- Image/video campaigns use the same approved package prices and fair campaign rotation.
- Exact image/video pixel dimensions, codec/profile compatibility, thumbnail/poster handling, CTA types and upload validation remain technical design items.

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

Technical definitions for an impression, deduplication, click attribution, reporting time zone, reporting delay and bot filtering remain to be agreed before implementation. Do not promise guaranteed impression or click counts.

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

## 11. Open decisions before implementation

The following items still need explicit decisions or technical verification:
1. **Campaign capacity:** Should there be a maximum number of active campaigns, or should the system accept all approved campaigns and rotate them fairly?
2. **Advert categories and content rules:** Agree the permitted/prohibited categories and any legal disclosures required for the actual ad formats.
3. **Creative specifications:** Exact responsive pixel/export dimensions, image file types and size limit, video codec compatibility, crop behavior, poster/thumbnail handling, CTA options and upload validation. Image+video launch, shared portrait card presentation, MP4, 30-second and 20-MB video limits, muted visible-only autoplay and lazy loading are approved.
4. **Advert design deliverables:** Exact differences between Basic and Premium, output formats, source files and what counts as a revision.
5. **Advertiser dashboard access:** Email verification requirement, Google OAuth setup, account recovery and whether advertiser accounts require admin activation.
6. **Campaign editing after approval:** What changes require re-approval and whether a live campaign is paused during changes.
7. **Refund operations:** Expected refund processing window and how advertisers are notified.
8. **Analytics definitions:** Impression visibility threshold, click attribution, repeat views, reporting timezone and reporting delay.
9. **Bank details and reference format:** Secure configuration of the business account details and unique reference scheme; do not hardcode sensitive bank details in frontend source.
10. **Applicable regulatory review:** Confirm which advert categories and formats require pre-publication clearance under current Nigerian requirements.

## 12. Proposed implementation sequence (not yet authorized)

1. Complete the open product and legal decisions.
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
