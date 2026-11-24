# Member activity and notification automation

## Story notifications

When a member uploads a Story, The Match creates a single activity notification for eligible existing connections. The notification is sent only when the recipient can view the Story under its audience setting:

- `everyone` Stories use the same reciprocal preference, profile completeness, age, photo, dating-lane, block, and moderation checks as Story visibility.
- `matches` Stories are limited to mutual matches and exclude blocked or moderated members.
- A recipient receives at most one Story-upload notification from the same member within a 12-hour window.
- The existing `send-notification` database webhook sends the notification through OneSignal. The push opens the safe in-app destination supplied by the notification row.

## Inactive-member reminders

The re-engagement scheduler uses a separate private app-presence record, not `member_consistency.last_active_date`, which remains reserved for daily check-in streaks and rewards.

The lightweight `member-presence.js` client records presence on sign-in/app start, when the app returns to the foreground, and during member interaction, with a ten-minute write throttle. Existing members are seeded from their last Auth sign-in.

The daily job sends a friendly reminder after seven days without app activity, at most twice and at least fourteen days apart. Returning to the app resets the reminder sequence. Banned and currently suspended accounts are excluded. The schedule runs at 08:15 Nigeria time.

## Member-facing disclosure

The messaging area explains that conversations are one-to-one but not end-to-end encrypted, and that authorised administrators may review messages for safety, moderation, and support. The privacy policy contains the fuller disclosure. Admin chat-review requests are recorded in the audit table.
