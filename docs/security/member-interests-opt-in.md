# Optional member interests — privacy and rollout notes

## Purpose

This change adds a private, member-controlled interest list and an explicit opt-in switch for future compatibility ranking. It is a data foundation only. It does not change Discover, Nearby, profile cards, chat, Stories, Premium, notifications, or the live frontend.

## Data model

- `interest_catalog` is a curated list of non-sensitive interest labels. Signed-in members can read active choices; clients cannot add or edit catalog rows.
- `member_interests` stores at most 20 selected catalog codes per member. Row-level security allows each member to read, add, or remove only their own selections.
- `member_interest_sharing` records whether that member has opted in to using their interests for compatibility ranking. A missing row means opted out. The default is false.
- The consent trigger records the consent version and server timestamp when a member turns sharing on. Turning sharing off clears both consent fields.
- A database trigger validates catalog entries and serializes concurrent additions before enforcing the 20-interest maximum.

## Privacy guarantees in this foundation

- No backfill: existing members receive no interest records and are not opted in.
- No public/anonymous access.
- No member can directly read another member's interest selections or sharing preference through these tables.
- No raw interest lists are returned through an RPC or endpoint in this change.
- No use of `profiles.interested_in`, gender identity, sexual roles, messages, photos, GPS, or location.
- No frontend integration, ranking integration, production deployment, or production database migration is performed by this pull request.

## Important authorization finding

The current `public.can_interact_with_member(target_user_id)` RPC only confirms that the caller is signed in, the target is not the caller, and neither member has blocked the other. It does not enforce suspension/ban status, Discover filter preferences, age preferences, profile completeness, or Discover visibility. It must not be treated as a complete candidate-eligibility check.

The current Discover functions and frontend have separate filtering responsibilities. Before any future endpoint reads another member's interests, that endpoint must use a server-side, verified eligibility path that covers moderation status, age and member preferences, profile visibility/completeness, blocks, and both members' explicit opt-in. It must not trust candidate IDs or interests supplied by a browser.

## Required verification before applying this migration

1. Apply only to an isolated Supabase development branch/database first, never directly to the live project.
2. Confirm all three tables have RLS enabled and only the documented authenticated grants.
3. As member A, add and remove interests; verify member A can see only member A's rows.
4. As member B, verify member B cannot select, insert, update, or delete member A's rows or preference.
5. Verify anonymous requests cannot read the catalog or member tables.
6. Verify the catalog returns active choices only and clients cannot insert or edit catalog entries.
7. Verify a member can select 20 interests but the 21st distinct interest is rejected, including concurrent insert attempts.
8. Verify duplicate interests are rejected by the primary key.
9. Verify opt-in defaults to false, the consent timestamp/version are written on opt-in, and both are cleared on opt-out.
10. Verify deleting a member account cascades their own preference and interest rows.
11. Run Supabase security and performance advisors and review every finding.
12. Only after staging verification, request a separate approval before merging or applying to production.

## Next phase (not included)

Build a trusted backend flow that obtains interest selections from the database, checks both members' opt-in and full Discover eligibility, then passes only the minimum required data to the ranking engine. The browser must never receive the service token or a general-purpose endpoint for querying arbitrary members' interests.
