# The Match coin wallet implementation

## Approved product decisions
- Coin packs: 50 / ₦1,000; 120 / ₦2,000; 260 / ₦4,000; 700 / ₦10,000; 1,500 / ₦20,000.
- Payment: manual MTN MoMo transfer and administrator verification. Coins are credited only after an admin approves a pending request.
- Match Plus: 30 days / 300 coins.
- Match Quarterly: 90 days / 800 coins.
- Match Annual: 365 days / 2,800 coins.
- Active Match Annual members are eligible for 50 bonus coins every 30 days. The grant is currently manual and admin-only; no scheduler exists.
- Store prices remain listed, but Store purchases are disabled until secure fulfillment exists.
- Existing Premium pricing, Match Lite pricing and existing authentication flows must remain unchanged.

## Branch contents
- Wallet foundation migration: wallet, append-only ledger, transfer requests, membership records, store inventory/purchase records, RLS, and admin/member RPCs.
- Entitlement migration: active tier helper, Quarterly/Annual unlimited swipes, Match Plus Nearby access, tier-based Rewind and Boost rules, Story limits, and membership checkout RPC.
- `coin-wallet.js`: wallet UI, manual transfer submission, balance/history, membership catalogue, disabled Store catalogue and admin review queue.
- `index.html`: wallet script integration and tier feature checks.

## Confirmed live-schema integration findings
- The live Likes and Passes triggers use `enforce_daily_swipe_limit()`, not `enforce_daily_like_limit()`. The staged migration now updates the function actually attached to the live trigger and preserves the existing 20 total daily swipe cap, Premium and Match Lite unlimited access, and adds unlimited swipes for Quarterly/Annual.
- The live Stories trigger is already attached to `enforce_story_upload_limit()`. The staged migration now replaces that existing function rather than stacking a second Story trigger. Free/Lite retain one Story item per rolling 24 hours; Plus gets three per Lagos calendar day; Quarterly/Annual/Premium are unlimited.
- Rewind validates that a swipe can be undone before consuming the daily allowance and serializes per-member requests.
- Boost activation uses a per-member advisory lock to prevent simultaneous requests bypassing the cooldown.
- Admin checks use the existing `app_admins` table; the live `is_match_admin()` function and coin RPC admin check both reference that table.

## Tier benefits currently connected
- Match Plus: secure Nearby access, up to 3 Rewinds per Lagos day and up to 3 Stories per Lagos day. It does not receive unlimited swipes.
- Match Quarterly: unlimited swipes, up to 10 Rewinds per Lagos day, unlimited Stories and one 30-minute Profile Boost every 7 days.
- Match Annual: Quarterly benefits, unlimited Rewinds and one 30-minute Profile Boost every 24 hours. The 50-coin monthly reward requires a manual admin grant.
- Premium retains its existing unlimited swipes, Nearby, unlimited Rewinds and 24-hour Boost cooldown.
- Advanced Discovery filters remain Premium-only until the Match tier-specific filters are fully implemented. The UI must not promise unavailable benefits such as Incognito browsing, read receipts, priority visibility, or a decorative membership badge.
- Match Plus is not treated as Premium globally. Existing Premium/Lite records and prices are not rewritten.

## Safety and incomplete integrations
- The migrations are staged in PR #114 and have NOT been applied to production. No wallet rows, balances, transfer approvals or memberships have been created or changed.
- No Windows backup is available. Live testing is the agreed route, but database migrations must still be reviewed carefully before application because a bad production DDL change can be difficult to reverse.
- The bank transfer account is reused from the existing Premium flow and must be confirmed before public coin purchases are enabled.
- Coin approval/rejection notifications are in-app only; coin-specific email delivery is not connected.
- Store item purchases remain disabled. Super Likes, Extra Likes, Priority Visibility, badges and animated effects need server-side fulfillment before coins can be deducted.
- Annual bonus grants are manual; do not describe them as automatic.

## Required validation before merge
1. Complete static review of both SQL migrations and frontend integration.
2. Apply the migrations in a controlled order to the live project only after confirming the exact SQL and expected impact.
3. Test wallet creation, pack selection, duplicate transfer references, pending requests, admin approval/rejection, duplicate approvals, balance/ledger consistency and RLS isolation.
4. Test each tier with controlled member accounts and confirm swipe, Nearby, Rewind, Boost and Story behavior.
5. Regression-test login, signup, Discover, Nearby, chat, verification, Premium and Match Lite.
6. Confirm the bank-transfer account and admin queue on the live website.
7. Merge only after the live checks pass. Render deployment must be checked separately.
