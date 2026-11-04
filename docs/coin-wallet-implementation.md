# The Match coin wallet implementation

## Approved product decisions
- Coin packs: 50 / ₦1,000; 120 / ₦2,000; 260 / ₦4,000; 700 / ₦10,000; 1,500 / ₦20,000.
- Payment: existing MTN MoMo bank-transfer account and manual administrator verification. Coins are credited only by the admin review RPC after a pending request is approved.
- Match Plus: 30 days / 300 coins.
- Match Quarterly: 90 days / 800 coins.
- Match Annual: 365 days / 2,800 coins.
- Active Match Annual members receive 50 bonus coins every 30 days.
- Match Store prices: 40 coins for one 24-hour boost; 100 for three boosts; 10 for one Super Like; 45 for five; 30 for 10 Extra Likes; 75 for 30 Extra Likes; 100 for 7-day Priority Visibility; 250 for 30-day Priority Visibility; 100 for a decorative profile badge; 150 for an animated profile effect.
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

## Required next validation
1. Apply the migration only to a disposable Match development database and check all RLS/grants and function execution privileges.
2. Test member isolation, duplicate transfer references, pending/review state transitions, duplicate approvals, concurrent wallet spends, insufficient balance and idempotency.
3. Fix and test annual reward concurrency and schedule before launch.
4. Connect each tier to the correct existing feature gates without removing any Premium/Lite benefit.
5. Connect each store item to a secure fulfillment path before enabling purchase buttons.
6. Test as anonymous, regular member and admin; regression-test login, signup, Discover, Nearby, chat, verification, Premium and Match Lite.
7. Only then prepare a production migration and deployment plan. This branch is not merged or deployed.
