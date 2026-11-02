# Android push notification setup

The Match uses OneSignal Web SDK v16. Chrome on Android displays an app-icon notification dot when an installed PWA receives an unread system push notification. It does not support a programmable numeric badge on the PWA icon; the numeric unread total remains inside The Match.

## One-time configuration

1. In OneSignal, open the **The Match** app (app ID: `c5deb192-536d-4498-ba4b-b973d50d5ba6`).
2. Open **Settings → Keys & IDs** and copy the **REST API Key**. Do not put this key in the website, GitHub, or a chat message.
3. In Supabase, open project **the-match-dating-app** → **Edge Functions → Secrets**. Add:
   - Name: `ONESIGNAL_REST_API_KEY`
   - Value: the REST API Key copied from OneSignal.
4. Deploy the Edge Function `send-notification` with JWT verification disabled. The handler validates the Supabase project secret key supplied by the Database Webhook in its `apikey` header.
5. In Supabase, open **Database → Webhooks → Create a new webhook**:
   - Name: `send-match-push-notification`
   - Table: `public.notifications`
   - Events: **Insert** only
   - Type: **Supabase Edge Functions**
   - Function: `send-notification`
   - Add the project's Supabase **secret key** as the webhook's secret key / `apikey` header. Do not use the publishable/anon key.
6. Save the webhook.

The database webhook sends each new unread notification to the Edge Function. The function targets the matching OneSignal user by the Supabase Auth user UUID and never exposes the OneSignal REST API key to the browser.

## Member device setup

1. Open The Match from Chrome on Android.
2. Sign in, then go to **Settings → Push notifications → Turn on notifications**.
3. Accept the browser/Android notification permission prompt.
4. Install The Match to the home screen if it is not already installed. On Android, the system notification dot appears when a push arrives while the app is not actively open. The exact appearance depends on Android launcher notification settings.

Members who previously blocked notifications must enable them in Android **Settings → Apps → Chrome → Notifications** (or Chrome's site settings for The Match), then return to The Match and opt in.

## Safety notes

- Never commit the OneSignal REST API key or Supabase secret key.
- Push notifications are sent only for newly inserted rows in `public.notifications`.
- The app's existing in-app unread count and read/unread behavior remain unchanged.
- Android Chrome PWA icons show a dot, not a numeric count. Numeric app-icon badges require a native Android app and launcher support.
