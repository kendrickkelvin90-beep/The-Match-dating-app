# Backblaze B2 media migration

## Safety rules

- This migration is opt-in and admin-only. It is not run automatically on deploy.
- Copy each object to B2 first, then conditionally update its database reference.
- Never delete the Supabase source object during this migration.
- Re-running a batch is safe: the B2 object key is deterministic for a source row.
- Process at most two objects per request; each source object must be 25 MB or smaller.
- A row is counted as migrated only after the database reference update succeeds.
- New profile photos, Stories, regular chat attachments, verification selfies, and event posters are routed to B2 by the branch code.
- Chat View Once attachments intentionally remain in Supabase until their atomic one-time access flow is migrated and tested.
- Verify application reads for every media category before any later source cleanup.

## Categories

| Category | Supabase bucket | Table / path column | B2 marker |
| --- | --- | --- | --- |
| Profile photos | profile-photos | profile_photos.storage_path | b2:// |
| Stories | story-media | stories.media_url | b2:// |
| Chat media | chat-media | chat_media.storage_path | b2:// |
| Verification selfies | verification-selfies | verification_requests.selfie_path | b2:// |
| Event posters | event-posters | match_event_poster_assets.storage_path | b2:// |

## Backblaze bucket CORS prerequisite

New browser uploads use short-lived presigned PUT URLs so large videos do not pass through a Supabase Edge Function. Before enabling the new upload code, configure the B2 bucket's CORS rules to allow the app origin `https://match.beyondthebinarymedia.online`, method `PUT`, and request header `Content-Type`. Keep the origin restricted to the production app domain; do not use a wildcard origin. Signed GET downloads do not require exposing the bucket publicly.

## Automatic Story migration

The Story reader already supports `b2://` media references, and new Story uploads are routed to B2. The app now starts a background migration automatically when an administrator signs in. It processes two legacy Story objects per batch, waits briefly between batches, resumes on a later admin session after a transient failure, verifies the B2 copy before changing the database reference, and leaves the original Supabase object untouched. No migration button is required. Keep the administrator session signed in while the first migration run is progressing.

The browser-driven worker pauses when the administrator closes the app or signs out; it resumes automatically on the next administrator sign-in. A fully unattended server-side schedule would require a separately provisioned, securely stored server credential and is not enabled by this change.

## Manual worker fallback (for diagnostics only)

Call the `b2-media-migrate` Edge Function with the signed-in administrator session:

```json
{ "category": "profile_photos", "limit": 2 }
```

Repeat with each category key: `stories`, `chat_media`, `verification_selfies`, and `event_posters`. Continue a category until its returned `remaining` count is zero. For `chat_media`, `remaining` excludes View Once records; those are separately reported as `excludedViewOnce`. A failed item is returned in `failures`; inspect and resolve it before continuing.

The current Story reader resolves B2 URLs through the authenticated `b2-media-access` function. Chat media, verification selfies, and event posters still require their own read-path rollout before their existing records can safely be migrated. Do not migrate those categories as part of the Story worker.

## Completion checks

1. Each category returns `remaining: 0`.
2. Compare B2 object counts and sizes against source rows.
3. Sign in as ordinary members and test their own profile photos, Discover, Nearby, stories, and chat media.
4. Test chat View Once behavior and verify non-participants cannot fetch chat attachments.
5. Test admin-only verification selfie review and event poster visibility.
6. Confirm no source objects are deleted until a separate retention/cleanup decision is approved.
