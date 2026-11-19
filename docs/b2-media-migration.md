# Backblaze B2 media migration

## Safety rules

- This migration is opt-in and admin-only. It is not run automatically on deploy.
- Copy each object to B2 first, then conditionally update its database reference.
- Never delete the Supabase source object during this migration.
- Re-running a batch is safe: the B2 object key is deterministic for a source row.
- Process at most two objects per request; each source object must be 25 MB or smaller.
- A row is counted as migrated only after the database reference update succeeds.
- Verify application reads for every media category before any later source cleanup.

## Categories

| Category | Supabase bucket | Table / path column | B2 marker |
| --- | --- | --- | --- |
| Profile photos | profile-photos | profile_photos.storage_path | b2:// |
| Stories | story-media | stories.media_url | b2:// |
| Chat media | chat-media | chat_media.storage_path | b2:// |
| Verification selfies | verification-selfies | verification_requests.selfie_path | b2:// |
| Event posters | event-posters | match_event_poster_assets.storage_path | b2:// |

## Running the worker (after application B2 read support is deployed)

Call the `b2-media-migrate` Edge Function with the signed-in administrator session:

```json
{ "category": "profile_photos", "limit": 2 }
```

Repeat with each category key: `stories`, `chat_media`, `verification_selfies`, and `event_posters`. Continue a category until its returned `remaining` count is zero. A failed item is returned in `failures`; inspect and resolve it before continuing.

**Do not run the worker until the matching app read path has been deployed.** The current production app only resolves B2 profile-photo paths. Stories, chat media, verification selfies, and event posters still use Supabase Storage reads. Migrating those references before their readers are updated would make those assets temporarily unavailable.

## Completion checks

1. Each category returns `remaining: 0`.
2. Compare B2 object counts and sizes against source rows.
3. Sign in as ordinary members and test their own profile photos, Discover, Nearby, stories, and chat media.
4. Test chat View Once behavior and verify non-participants cannot fetch chat attachments.
5. Test admin-only verification selfie review and event poster visibility.
6. Confirm no source objects are deleted until a separate retention/cleanup decision is approved.
