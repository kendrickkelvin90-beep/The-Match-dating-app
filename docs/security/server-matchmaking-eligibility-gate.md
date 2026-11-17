# Server-side matchmaking eligibility gate

## Purpose

This is an additive foundation for a future interest-based ranking service. It creates one authenticated RPC that returns **candidate UUIDs only** after checking the server-side eligibility conditions that can currently be verified from the live schema.

It does not change the existing Discover RPC, Discover frontend, profile cards, Nearby, Stories, chat, Premium, notifications, or member data. It does not read or return member interests.

## Checks performed

The RPC public.matchmaking_eligible_candidate_ids(...):

- Requires an authenticated caller.
- Uses the live `is_match_profile_complete(user_id)` helper for the exact canonical profile-completeness rules, then requires at least two profile-photo records.
- Excludes a viewer who is currently suspended or permanently banned.
- Starts with the existing discover_profiles_secure candidate pool, preserving its age, city, distance, and reciprocal-block behavior.
- Rechecks reciprocal blocks directly rather than relying on the current live can_interact_with_member definition.
- Excludes candidates who are currently suspended or permanently banned.
- Requires each candidate to have a complete profile and at least two profile photos.
- Applies supported gender and role filters, plus mutual compatibility: the viewer's stated dating preference must accept the candidate's gender, and the candidate's stated dating preference must accept the viewer's gender.
- Applies the verified-only filter only for active Premium members.
- Returns only candidate IDs, with a hard maximum of 100 rows.
- Denies execution to anonymous and public roles.

The function is deliberately VOLATILE so repeated calls in a transaction can re-read current moderation and membership state rather than reuse a statement-level stable snapshot. Moderation uses the live member_moderation schema: permanent bans are always excluded; suspensions are excluded only while expires_at is in the future.

## Important limits discovered in the current app

The current live schema does not contain a separate profile-visibility/private-profile flag, so this RPC cannot enforce a setting that does not exist.

Some Discover behavior is still frontend-only. In particular:
- The current Recently active filter relies on browser-side presence and is not included in this server-side gate.
- The current connection-intention preference does not map cleanly to profiles.interested_in: the UI stores relationship intentions, while that profile column stores who a member wants to meet. It is intentionally not guessed or applied here.
- The current role filter checks the first item in sexual_roles; this RPC mirrors that behavior for compatibility. Sexual roles are now optional profile information and are not part of profile-completeness validation.
- The existing Discover RPC remains responsible for city, distance, and age filtering. Its current behavior is preserved rather than rewritten.

These limits must be resolved before claiming the backend exactly reproduces every frontend Discover preference.

## Future interest access contract

This RPC is not permission to read another member's interests. A later, separate backend-only read path must:
1. Authenticate the member making the request.
2. Obtain candidate IDs through this eligibility gate, not from browser-supplied arbitrary IDs.
3. Re-check eligibility at the moment of interest access.
4. Require the candidate to have explicitly opted in before their interests are shared or scored. The viewer's own selected interests may be used privately for that viewer's comparison and are never exposed to the candidate.
5. Read candidate interests only through the trusted shared-details boundary, which rechecks current Discover visibility, moderation, blocks, mutual gender preferences, straight-only audience rules, and candidate sharing consent.
6. The profile-details RPC may return candidate interest labels only because the candidate explicitly opted in to showing them; the separate interest-scoring RPC returns only a shared count and overlap percentage, never raw arrays.
7. Never expose the matchmaking service token or Supabase service-role key to the browser.

The onboarding sexual-orientation answer is stored in member_onboarding.answers, not in the public profiles table. It is identity information and is not used as a substitute for explicit dating preferences. The Python ranking prototype remains disconnected from live member data.

## Verification and rollout

CI runs the migration and assertions against a disposable PostgreSQL 17 database with synthetic accounts. Its setup now mirrors the live moderation constraints and photo column types, and includes regression cases for placeholder profile data and missing primary photos. This is still not a Supabase staging test.

Before any staging or production use:
- Verify the function against the exact live migration state in an isolated Supabase environment.
- Review the existing Discover RPC and all current preference semantics again.
- Test expired and active suspensions, permanent bans, reciprocal blocks, missing photos, incomplete profiles, age and city filters, role and gender filters, Premium gates, and concurrent requests.
- Run Supabase security and performance advisors.
- Obtain separate approval before applying any migration to the live project.

This feature branch includes an optional-role profile migration and limited onboarding/profile/public-copy changes. The eligibility RPC is still not integrated into the live Discover flow, and no production migration has been applied.


## Shared-interest compatibility scoring

The general-dating branch adds `public.get_interest_match_scores(uuid[])`. It calls the existing shared-details RPC inside a trusted security-definer boundary, so a candidate is scored only when that member is currently visible through Discover and has explicitly opted in to sharing interests. Lifestyle-only sharing does not enable interest scoring.

The browser receives only:
- the number of interests in common; and
- a Jaccard overlap percentage (shared interests divided by the union of the two selected-interest sets).

It does not receive another member's raw interest array through this scoring RPC. Discover can use the score to order profiles when the member enables the shared-interest priority preference, and the card labels the figure as interest overlap rather than an overall compatibility guarantee.

The profile editor also displays a live 10-interest selection counter and disables additional unselected options once the limit is reached. The database trigger remains the authoritative validation boundary.


## Adults-only write enforcement

The database migration `20261116190000_adult_age_enforcement.sql` adds a trigger that rejects profile inserts or age updates below 18. It does not rewrite existing profile rows; the server-side completeness and Discover gates independently exclude any legacy under-18 record. The browser age check is only a convenience and is not the security boundary.
