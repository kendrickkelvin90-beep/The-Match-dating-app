# The Match coin wallet implementation

## Approved product decisions
- Coin packs: 50 / ₦1,000; 120 / ₦2,000; 260 / ₦4,000; 700 / ₦10,000; 1,500 / ₦20,000.
- Payment: existing MTN MoMo bank-transfer account and manual administrator verification. Coins are credited only by the admin review RPC after a pending request is approved.
- Match Plus: 30 days / 300 coins.
- Match Quarterly: 90 days / 800 coins.
- Match Annual: 365 days / 2,800 coins.
- Active Match Annual members receive 50 bonus coins every 30 days.
- Match Store prices: 40 coins for one 30-minute boost; 100 for three boosts; 10 for one Super Like; 45 for five; 30 for 10 Extra Likes; 75 for 30 Extra Likes; 100 for 7-day Priority Visibility; 250 for 30-day Priority Visibility; 100 for a decorative profile badge; 150 for an animated profile effect.
- Match Plus/Quarterly/Annual benefit allocation follows the previously reviewed tier outline in the app's wallet UI. Annual includes all lower-tier benefits plus its additional annual benefits.
- Existing Premium pricing and Match Lite are out of scope and must remain unchanged.

## Current branch contents
- `supabase/migrations/20261104180000_coin_wallet_bank_transfer_foundation.sql`: wallet, append-only ledger, manual coin purchase requests, Match Plus membership records, inventory, purchase records, owner-only read policies, and server-side RPCs for request submission, admin review/crediting, coin spending and annual bonus grants.
- `coin-wallet.js`: member wallet screen, bank transfer instructions, package request submission, balance/ledger/request history, admin transfer review queue, and visible Match Plus/store catalogue.
- `index.html`: loads the wallet script without rewriting the existing authentication flow.

## Safety and incomplete integrations
- This branch has not applied its migration to the live Supabase project. Do not deploy the frontend before applying and testing the migration in an isolated database.
- The Match Plus tier records are separate from existing Premium and Lite entitlements. The UI intentionally does not offer membership activation yet: feature gates throughout Discover, Nearby, Stories, messaging, Rewind and Boost must be mapped and tested before coin debit is enabled for a tier. Do not silently convert Match Plus to Premium or modify current Premium membership rows.
- Store catalogue buttons remain disabled until each purchased item is connected to real feature fulfillment. In particular, decorative badges must never resemble identity verification; Super Likes, Extra Likes and Priority Visibility need their own server-enforced behavior.
- Annual bonus grant is currently an admin-only RPC and is not scheduled. Add a secure recurring schedule and test idempotency before production launch.
- Coin purchase rejection/approval notifications are in-app notifications. Coin-specific email delivery has not been connected.
- The bank account shown is reused from the existing Premium transfer flow. Verify the account details in the production app before public release.
- No production DDL, payment approval, wallet credit, or membership mutation was performed.

## Existing feature-gate findings
- The current Discover boost action calls `activate_my_profile_boost()` and is explicitly Premium-only; the existing boost window is 30 minutes. The coin Store label now reflects 30 minutes, not 24 hours. Coin-purchased boosts need a separate server-side fulfillment path and must not bypass Premium authorization by calling the existing RPC unsafely.
- Existing Rewind is also explicitly Premium-only and calls `rewind_my_last_swipe()`; the current swipe-limit bypass is shared by Premium and Match Lite. Match Plus tier benefits therefore need deliberate server-side entitlement checks rather than changing Premium/Lite checks globally.
- The existing database exposes `is_match_admin()` for the admin queue; the coin migration adds a separate `coin_is_admin()` helper. Both are admin-gated, but the deployed function behavior and grants still need test coverage.

## Tier feature-gate integration staged on this branch
- Added a second migration defining a current-member-only Match Plus tier helper and server-side unlimited-swipe entitlement for Quarterly/Annual, while preserving existing Premium and Match Lite unlimited swipes.
- Connected the secure Nearby RPC to active Match Plus tiers without exposing precise coordinates or changing the 50 km cap.
- Connected server-side Rewind allowances: Plus 3/day, Quarterly 10/day, Annual unlimited; Premium remains unlimited. Usage counters are keyed to the Lagos calendar day.
- Connected Profile Boost eligibility: Quarterly once every 7 days, Annual once every 24 hours, Premium retains its existing 24-hour cooldown; boosts remain 30 minutes.
- Added server-side Story creation limits: Plus 3 per Lagos day; Quarterly/Annual/Premium unlimited; Free/Lite retain one active Story. This must be regression-tested against current Story creation UX.
- Enabled Match Plus membership checkout through a dedicated authenticated RPC. Active higher tiers cannot be downgraded by buying a lower tier.
- Updated Discover and Nearby controls to recognize the relevant Match Plus entitlements without treating Match Plus as Premium globally.
- Store item purchases remain disabled; no inventory debit can happen before real item delivery is connected.
- Annual 50-coin reward remains a manual admin-only grant; no recurring schedule is configured.

## Required next validation
1. Apply the migration only to a disposable Match development database and check all RLS/grants and function execution privileges.
2. Test member isolation, duplicate transfer references, pending/review state transitions, duplicate approvals, concurrent wallet spends, insufficient balance and idempotency.
3. Fix and test annual reward concurrency and schedule before launch.
4. Connect each tier to the correct existing feature gates without removing any Premium/Lite benefit.
5. Connect each store item to a secure fulfillment path before enabling purchase buttons.
6. Test as anonymous, regular member and admin; regression-test login, signup, Discover, Nearby, chat, verification, Premium and Match Lite.
7. Only then prepare a production migration and deployment plan. This branch is not merged or deployed.
