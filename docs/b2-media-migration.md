# Backblaze B2 media migration

## Safety rules

- Legacy Story media is migrated by a Supabase server-side scheduled worker; no administrator needs to keep the app open or press a migration button.
- The worker copies each object to B2 first, then conditionally updates the matching database reference.
- Original Supabase Storage objects are retained. This migration never deletes source files.
- B2 object keys are deterministic for each source row, so retrying a partially completed copy is safe.
- Each invocation processes at most two objects and accepts source objects up to 25 MB.
- A database reference is changed only after the B2 upload succeeds.
- Failed records are retried with increasing backoff, up to five attempts. Permanently failing records remain in Supabase and are recorded in `public.b2_media_migration_failures` for administrator review.
- Chat View Once attachments remain in Supabase until their atomic one-time access flow is separately migrated and tested.

## Categories

| Category | Supabase bucket | Table / path column | B2 marker |
| --- | --- | --- | --- |
| Profile photos | profile-photos | profile_photos.storage_path | b2:// |
| Stories | story-media | stories.media_url | b2:// |
| Chat media | chat-media | chat_media.storage_path | b2:// |
| Verification selfies | verification-selfies | verification_requests.selfie_path | b2:// |
| Event posters | event-posters | match_event_poster_assets.storage_path | b2:// |

Profile photos are already using B2. This automated job targets legacy Story records only; other categories remain outside its scope.

## Automatic Story migration

The migration uses Supabase Cron (`pg_cron`) and `pg_net` to invoke the existing `b2-media-migrate` Edge Function once per minute while eligible legacy Story rows remain. The scheduler credential is generated inside the database and stored encrypted in Supabase Vault. The Edge Function validates that credential through a service-role-only database function. No B2 credential or scheduler token is placed in browser code or committed to the repository.

The worker:
1. Selects up to two eligible legacy Story records.
2. Downloads the original object from the private Supabase `story-media` bucket.
3. Copies it to the private B2 bucket using a deterministic object key.
4. Updates the Story's `media_url` only after the B2 copy succeeds.
5. Records failures and retries them with backoff; after five failed attempts, it leaves the original intact and flags the record for admin review.
6. Stops its cron job when no retryable legacy Story records remain.

The Story reader already supports `b2://` references through the authenticated `b2-media-access` Edge Function. The scheduler is activated by the database migration and the updated Edge Function deployment. After that one-time rollout, the media migration itself runs unattended, including when no one is signed in or has the app open.


## Member activity reminders

The re-engagement scheduler uses a separate private app-presence record, not `member_consistency.last_active_date` (which remains reserved for daily check-in streaks and rewards). The lightweight `member-presence.js` client records presence on sign-in/app start, when the app returns to the foreground, and during member interaction, with a ten-minute write throttle. Existing members are seeded from their last Auth sign-in. The daily job sends a friendly reminder after seven days without app activity, at most twice and at least fourteen days apart; returning to the app resets the reminder sequence. Banned and currently suspended accounts are excluded.

## Completion and verification

- Confirm the scheduled job appears in Supabase Cron as `automatic-b2-story-media-migration`.
- Monitor `cron.job_run_details` for successful invocations.
- Confirm Story records transition from Supabase paths to `b2://` references.
- Check `public.b2_media_migration_failures` for any records that exhausted retries.
- Test Story playback as an ordinary member after migration.
- Keep all original Supabase source objects until B2 playback has been verified and a separate retention decision is approved.

## Important rollout boundary

This pull request prepares the automatic worker, scheduler migration, and secure function authentication. It does not apply the production database migration or deploy the production Edge Function by itself. The live migration starts only after both are rolled out. No live database or B2 object has been modified by this code change.
