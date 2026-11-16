# The Match — Python matchmaking foundation

This isolated, stateless prototype ranks a caller-supplied set of eligible candidates using Jaccard similarity over interests explicitly selected by members.

## Current scope

- `GET /health` provides a basic health response.
- `POST /v1/matchmaking/rank` ranks 1–100 candidate records using up to 30 explicit interests per member.
- Results include shared-interest explanations. Scores use the Jaccard formula: shared interests divided by the union of both interest lists, expressed as a percentage.
- The engine is deterministic and does not store requests or member data.
- Ranking requires two credentials: a backend-held `MATCHMAKING_SERVICE_TOKEN` and a member's Supabase access token in `X-Member-Authorization`.
- The service verifies the member token against Supabase Auth `/auth/v1/user`, then calls the existing `can_interact_with_member` RPC using that same member token for every candidate. The existing RPC enforces two-way blocks and current suspension/ban status. No service-role key is used.

## Important data limitation

The live Match database currently exposes `profiles.interested_in`, which is a relationship/gender preference, not a list of hobbies or shared interests. The matchmaking engine must **not** use `interested_in`, gender identity, sexual roles, private messages, photos, or location as interest-similarity inputs. A separate, explicit, member-controlled interests source and consent model must be designed before this ranking engine can use real member data. Until then, test only with synthetic interest lists.

## Privacy and safety boundaries

- No Supabase schema, production data, frontend, or production traffic is changed or connected by this PR.
- The service token is a service-to-service gate, not member authentication. Store it only in a trusted backend secret manager; never put it in browser JavaScript, a mobile app, source control, or client-visible configuration.
- The member token must be forwarded by a trusted backend. Do not expose this service directly to browser clients or send the service token to a client.
- Candidate eligibility is checked with the existing member-scoped RPC. If Supabase Auth or the RPC is unavailable, the service fails closed and returns a temporary-unavailable response.
- Use UUID candidate IDs only. Do not send names, emails, phone numbers, or raw profiles.
- No public production deployment. Before staging exposure, build a trusted backend caller that sources candidate IDs and consented interests from authoritative records, add host/edge rate limiting, logging minimization, secret rotation, and controlled test accounts.
- Set exact origins in `APP_ORIGINS`. Wildcard origins are rejected. CORS is not authentication.

## Required environment

- `MATCHMAKING_SERVICE_TOKEN`: high-entropy secret shared only between the trusted backend and this service.
- `SUPABASE_URL`: The Match Supabase project URL.
- `SUPABASE_ANON_KEY`: publishable/legacy anon key only; never a service-role key.
- `APP_ORIGINS`: exact allowed origins if browser preflight is required for a trusted backend caller.

## Local run

```bash
python -m venv .venv
. .venv/bin/activate
pip install -r requirements-dev.txt
pytest -q
uvicorn app.main:app --reload --port 8080
```

Run commands from this directory. The health endpoint works without credentials. Ranking requires `Authorization: Bearer <MATCHMAKING_SERVICE_TOKEN>` and `X-Member-Authorization: Bearer <member Supabase access token>`.

## Next milestone

Create a separate, member-controlled interests data model and trusted backend caller, with explicit opt-in and privacy-reviewed RLS. Then validate the full flow in staging using synthetic/test accounts. Production integration requires a separate review and explicit approval.
