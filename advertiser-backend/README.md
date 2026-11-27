# Isolated advertiser backend

This directory is the foundation for The Match's separate advertiser Supabase project. It is intentionally outside the existing `supabase/` directory so the Match member project cannot accidentally apply these tables or triggers.

## Non-negotiable separation

- Create a **separate Supabase project** for advertisers.
- Never run `database/bootstrap.sql` in the Match member project.
- Never use the Match member Auth client/session in the advertiser portal.
- Never expose a service-role/secret key, B2 key, payment bank configuration or analytics HMAC secret in browser code.
- The SQL bootstrap creates advertiser-only tables and an advertiser-project Auth trigger. It must not be installed in the Match project.
- The existing Match B2 upload/access functions remain unchanged. Sponsored creatives require a separate, advertiser-authenticated upload/access service.

## Files

- `database/bootstrap.sql`: initial advertiser schema, owner/admin RLS, campaign metrics RPC and advertiser Auth profile trigger.
- `database/verify.sql`: post-install privilege/RLS assertions.

## Required server-side configuration before deployment

- Advertiser project `SUPABASE_URL`, publishable/anon key and service-role secret.
- Google OAuth provider credentials and advertiser-project redirect URLs.
- Email delivery configuration for verification and recovery.
- B2 advertising-prefix credentials (separate key, scoped as narrowly as Backblaze supports).
- Advertising bank transfer display settings: bank name, account name and account number. Supply only to an authenticated advertiser after campaign creation; do not commit them.
- Analytics HMAC secret for deriving daily pseudonymous viewer keys.
- Match project URL and publishable key only for verifying member sessions in the ad-serving/analytics path.

## Important implementation notes

The SQL bootstrap is a setup script, not a production migration. It has not been run against a live advertiser project and has not passed a database test run yet. The schema is intentionally write-restricted: browser clients can read their own campaign/payment/design records, while server-side functions perform campaign creation, payment submission, payment confirmation, approval, scheduling, refunds, media writes and analytics writes.

Do not turn on the Discover integration until advertiser authentication, campaign state transitions, B2 private media delivery, analytics deduplication and member regression tests pass.
