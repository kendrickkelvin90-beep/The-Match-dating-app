# The Match — Rust chat service foundation

This is an isolated Rust/Axum service for The Match. It is intentionally separate from the existing static JavaScript application and Supabase Edge Functions.

## Current scope

- `GET /health`: service health check.
- `POST /v1/chat/authorize`: validates the caller's Supabase access token through Supabase Auth, then calls the existing `can_interact_with_member` RPC using that same member token.
- No service-role key is used.
- No message rows, media, profiles, subscriptions, or database schema are modified.
- The current browser chat flow is not connected to this service yet.

## Configuration

Set these environment variables in the hosting service:

- `SUPABASE_URL`: existing Supabase project URL.
- `SUPABASE_ANON_KEY`: Supabase publishable/anon key (not a service-role key).
- `PORT`: optional; defaults to `8080`.
- `RUST_LOG`: optional; defaults to an informational log level.

Never commit secrets to this repository.

## Local run

From the repository root:

```sh
cd services/chat-rust
cargo fmt --check
cargo test
cargo run
```

## API

`POST /v1/chat/authorize`

Headers:

```
Authorization: Bearer <member_supabase_access_token>
Content-Type: application/json
```

Body:

```json
{ "target_user_id": "00000000-0000-0000-0000-000000000000" }
```

A successful response is `200 { "authorized": true }`. Invalid sessions return 401; blocked or otherwise disallowed conversations return 403. The endpoint does not send messages.

## Deployment safety

Deploy as a separate service (for example, a separate Render Web Service using this Dockerfile). Do not change the existing website service, its start command, its domain, or its environment. Do not route production chat traffic to this service until the endpoint has been tested against a staging project and a controlled test account.

Before browser integration, configure a strict CORS allowlist for the production app origin and add request throttling. The current service is not yet intended for direct browser integration.
