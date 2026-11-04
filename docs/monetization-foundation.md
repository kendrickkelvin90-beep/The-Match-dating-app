# The Match monetization foundation

## Delivery approach
- Work only on `test/monetization-foundation-2026-11-04` until Kelvin approves testing.
- Keep the existing Premium plans and Match Lite offer unchanged.
- Do not change login, signup, Discover, Nearby, chat, profile verification, or existing admin controls as part of the first milestone.
- Build distinct, uncluttered Wallet, Store, and Transaction History pages/sections. Keep the member-facing experience friendly and accessible in dark and light themes.
- The current visual preview is `previews/match-store-preview.html`. It is intentionally standalone and uses only in-memory UI state; it does not connect to member data or payment services.

## Existing database findings (read-only inspection of production)
- Existing tables include `profile_boosts`, `referral_codes`, `referrals`, and `referral_rewards`.
- Existing referral tables currently expose member-owned read policies; do not recreate these tables.
- `profile_boosts` exists but the inspected policy list did not show a policy for it. Review its RLS, grants, and current consumers before connecting any UI.
- No wallet or coin-ledger table was present in the public table inventory.
- Existing Premium tables are separate and must not be modified for this project.

## Safe implementation sequence
1. Obtain an isolated Supabase development database. The Supabase branch tool quoted **$0.01344/hour** for a database branch in the current organization. Do not create it until the owner explicitly approves this recurring cost.
2. Inspect the existing database schema, RLS, grants, admin authorization function, and app navigation in the isolated environment.
3. Design an append-only transaction ledger and wallet balance model. Never let a browser client directly set its own coin balance.
4. Implement server-side, atomic credit/debit operations with idempotency keys, ownership checks, and audit metadata. Purchases remain pending until a verified payment event/admin confirmation.
5. Connect the Wallet, Store, and History screens to authenticated RPCs; show no paid benefit until the corresponding transaction is confirmed.
6. Reuse existing boost/referral foundations only after validating their semantics and access controls.
7. Add admin review views and reconciliation tools after member flows pass.
8. Test RLS as anonymous, ordinary member, and admin; test duplicate payment callbacks, retries, concurrent spends, insufficient balances, refunds/reversals, and unauthorized reads/writes.
9. Run Supabase security/performance advisors and regression checks for login, signup, chat, Discover, Nearby, Premium and Match Lite.
10. Ask Kelvin to test the branch. Do not merge or deploy without approval.

## Preview pricing
The amounts in the HTML preview are illustrative only and are not approved prices. Confirm pricing, payment provider, fulfilment rules, refund policy, and applicable legal requirements before enabling purchases.

## Explicit non-goals for milestone one
- No live payment collection.
- No live coin crediting or spending.
- No production database changes.
- No changes to existing Premium pricing or entitlements.
- No merge to `main`.
