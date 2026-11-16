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
- Applies supported gender and role filters.
- Applies the verified-only filter only for active Premium members.
- Returns only candidate IDs, with a hard maximum of 100 rows.
- Denies execution to anonymous and public roles.

The function is deliberately VOLATILE so repeated calls in a transaction can re-read current moderation and membership state rather than reuse a statement-level stable snapshot. Moderation uses the live member_moderation schema: permanent bans are always excluded; suspensions are excluded only while expires_at is in the future.

## Important limits discovered in the current app

The current live schema does not contain a separate profile-visibility/private-profile flag, so this RPC cannot enforce a setting that does not exist.

Some Discover behavior is still frontend-only. In particular:
- The current Recently active filter relies on browser-side presence and is not included in this server-side gate.
- The current connection-intention preference does not map cleanly to profiles.interested_in: the UI stores relationship intentions, while that profile column stores who a member wants to meet. It is intentionally not guessed or applied here.
- The current role filter checks the first item in sexual_roles; this RPC mirrors that behavior for compatibility.
- The existing Discover RPC remains responsible for city, distance, and age filtering. Its current behavior is preserved rather than rewritten.

These limits must be resolved before claiming the backend exactly reproduces every frontend Discover preference.

## Future interest access contract

This RPC is not permission to read another member's interests. A later, separate backend-only read path must:
1. Authenticate the member making the request.
2. Obtain candidate IDs through this eligibility gate, not from browser-supplied arbitrary IDs.
3. Re-check eligibility at the moment of interest access.
4. Require both members to have explicitly opted in to interest sharing.
5. Read interests only inside a trusted backend boundary.
6. Return no raw interest lists to the browser; send only the minimum derived compatibility signal needed for ranking.
7. Never expose the matchmaking service token or Supabase service-role key to the browser.

The Python ranking prototype remains disconnected from live member data.

## Verification and rollout

CI runs the migration and assertions against a disposable PostgreSQL 17 database with synthetic accounts. Its setup now mirrors the live moderation constraints and photo column types, and includes regression cases for placeholder profile data and missing primary photos. This is still not a Supabase staging test.

Before any staging or production use:
- Verify the function against the exact live migration state in an isolated Supabase environment.
- Review the existing Discover RPC and all current preference semantics again.
- Test expired and active suspensions, permanent bans, reciprocal blocks, missing photos, incomplete profiles, age and city filters, role and gender filters, Premium gates, and concurrent requests.
- Run Supabase security and performance advisors.
- Obtain separate approval before applying any migration to the live project.

No production migration or frontend change is included in this PR.
