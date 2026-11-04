# The Match monetization foundation

## Delivery approach
- Work only on `test/monetization-foundation-2026-11-04` until Kelvin approves testing.
- Do not merge or deploy without explicit approval.
- Keep login, signup, Discover, Nearby, chat, verification, existing admin controls, Match Lite and production Premium entitlements protected during the transition.
- The current interactive design preview is `previews/match-plus-store-preview.html`. It is standalone and uses only in-memory UI state; it is not connected to member data, wallet services or payments.

## Proposed coin package pricing — awaiting Kelvin's final approval
| Package | Coins | Price |
|---|---:|---:|
| Starter | 50 | ₦1,000 |
| Popular | 120 | ₦2,000 |
| Value | 260 | ₦4,000 |
| Premium Bundle | 700 | ₦10,000 |
| Ultimate Bundle | 1,500 | ₦20,000 |

## Proposed Match Plus membership prices — awaiting Kelvin's final approval
| Tier | Duration | Coin cost | Proposed Naira reference price |
|---|---:|---:|---:|
| Match Plus | 30 days | 300 | ₦5,999 |
| Match Quarterly | 90 days | 800 | ₦15,999 |
| Match Annual | 365 days | 2,800 | ₦49,999 |

Match Annual also receives 50 bonus coins every 30 days while the annual membership remains active. Rewards must be issued idempotently, recorded in the ledger, and not duplicated by retries. Unclaimed/missed rewards are not retroactively paid unless a future policy explicitly says otherwise.

The Naira amounts are planning references only, not a final approved checkout price list. The actual checkout design must clearly distinguish purchasing coin packs from spending coins on membership, so the user is never charged twice for the same membership.

## Proposed individual Match Store prices — awaiting Kelvin's final approval
| Item | Coin cost |
|---|---:|
| Profile Boost (24 hours) | 40 |
| 3 Profile Boosts | 100 |
| 1 Super Like | 10 |
| 5 Super Likes | 45 |
| 10 Extra Likes | 30 |
| 30 Extra Likes | 75 |
| Priority Visibility (7 days) | 100 |
| Priority Visibility (30 days) | 250 |
| Special Profile Badge | 100 |
| Animated Profile Effect | 150 |

Official identity-verification badges must never be sold or imitated by decorative badges. Avoid charging a member twice for a benefit already included in their active Match Plus tier.

## Draft tier benefit allocation — requires comparison and approval before live fulfilment
The current Premium page in `index.html` (around lines 6060-6106 at the time of inspection) lists these benefits:
- See who likes you.
- Premium Nearby.
- Premium messaging.
- Read receipts.
- Swipe Rewind.
- Profile Boost (30 minutes).
- Premium badge.
- Advanced Discovery controls (expanded distance and age ranges, verified/recently-active filters, additional role preferences).
- Unlimited swipes (the current copy says free members can Like or Pass up to 20 profiles per day).
- Exclusive access to Premium features.

Draft allocation shown in the preview (not approved and not connected to live entitlements):
- Match Plus (30 days): see who likes you; Premium Nearby cards; expanded age/distance controls; verified and recently-active filters; 3 daily Rewinds; 3 Stories per day; Match Plus badge.
- Match Quarterly (90 days): everything in Match Plus; unlimited daily Likes; all advanced Discovery filters; 10 daily Rewinds; unlimited Stories; read receipts; priority profile visibility; one Profile Boost every 7 days; Quarterly badge.
- Match Annual (365 days): every Match Plus and Quarterly benefit; Incognito browsing; unlimited Rewinds; all Premium messaging benefits; one Profile Boost every 24 hours; Annual gold badge; future Annual-member benefits; 50 bonus coins every 30 days while active.

This is a product proposal, not a verified parity map. Before connecting these entitlements, inspect the full existing Premium page, actual feature gates, story limits, messaging behavior, swipe logic, filter controls, Nearby distance rules and any other current Premium-only benefits. Do not remove or downgrade any current paid entitlement by assumption. The final tier matrix must be explicitly confirmed.

## Existing Premium implementation facts — read-only source inspection
- The Premium page currently describes: See who likes you, Premium Nearby, more Stories, Premium messaging, read receipts, Swipe Rewind, a 30-minute Profile Boost, a Premium badge, Advanced Discovery controls, unlimited swipes, and exclusive Premium access.
- The current swipe-limit migration sets Free members to 20 combined Likes and Passes per Lagos calendar day; active Premium and Match Lite members bypass that cap. This is enforced in database triggers, not only by the UI.
- The current rewind RPC and Profile Boost RPC require an active `premium_memberships` row. The boost RPC creates a 30-minute boost and has a 24-hour activation cooldown. Do not silently change these rules when adding coin purchases.
- The Match Lite migration is a separate 30-day entitlement and grants unlimited swipes plus access to received Likes. It must remain distinct from full Premium.
- One historical migration in the branch currently constrains weekly Premium payment requests to ₦4,000. This is a code observation, not permission to change any Premium price. Kelvin has explicitly instructed that existing Premium prices remain untouched; verify the live source and obtain explicit direction before any Premium pricing edit.

## Existing production database findings (read-only inspection)
- Existing tables include `profile_boosts`, `referral_codes`, `referrals`, and `referral_rewards`.
- Existing referral tables currently expose member-owned read policies; do not recreate these tables.
- `profile_boosts` exists but its RLS, grants, and current consumers must be reviewed before connecting UI.
- No wallet or coin-ledger table was present in the public table inventory.
- Existing Premium tables `premium_memberships` and `premium_payment_requests` are separate and must not be modified as part of the preview milestone.
- The production project contains live member data. Do not run DDL or alter production entitlements for this work.
- The other existing Supabase project was inspected read-only. It has a separate `users` table with integer IDs and wallet/top-up/social-service order tables, unlike The Match's Supabase Auth UUID-based schema. It is not a safe drop-in Match development database and must not be repurposed without a separate explicit review.

## Safe implementation sequence
1. Finish the product and tier-benefit matrix using the current Premium code and confirm it with Kelvin.
2. Obtain an isolated Supabase development database. A Supabase branch was previously quoted at **$0.01344/hour**. Do not create it or incur that recurring cost without explicit approval. The second existing Supabase project has a different schema and appears to serve another app; do not use it as a Match dev database.
3. Inspect the isolated database schema, RLS, grants, admin authorization, existing referral and boost semantics, and app navigation.
4. Design an append-only transaction ledger and wallet model. Never let a browser client directly set its own coin balance.
5. Implement server-side atomic credit/debit operations with idempotency keys, ownership checks, audit metadata and safe reversals.
6. Keep payment pending until a verified provider event or admin confirmation. Never credit coins from a screenshot alone.
7. Connect wallet, coin store, Match Plus tiers and transaction history to authenticated server-side operations.
8. Implement annual 50-coin rewards with a unique period key so scheduled retries cannot double-credit.
9. Add admin review, controlled coin adjustments and a complete audit trail.
10. Test as anonymous, ordinary member and admin; test duplicate payment callbacks, retries, concurrent spends, insufficient balances, refunds/reversals, membership expiry/upgrades, annual rewards and unauthorized reads/writes.
11. Run Supabase security/performance advisors and regression checks for login, signup, chat, Discover, Nearby, profile verification, Premium transition and Match Lite.
12. Ask Kelvin to test the branch. Do not merge or deploy without explicit approval.

## Explicit non-goals for the current preview milestone
- No live payment collection.
- No live coin crediting or spending.
- No production database changes.
- No changes to existing Premium plans, payment requests or member entitlements; all coin and Match Plus prices remain proposals until Kelvin confirms them.
- No changes to login/signup, Discover, Nearby, chat, verification or Match Lite.
- No merge to `main` and no deployment.
