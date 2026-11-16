# The Match — Python matchmaking foundation

This isolated, stateless prototype ranks a caller-supplied set of eligible candidates using Jaccard similarity over interests that members explicitly choose to share.

## Current scope

- `GET /health` provides a basic health response.
- `POST /v1/matchmaking/rank` ranks 1–100 candidate records using up to 30 explicit interests per member.
- Results include shared-interest explanations. Scores use the Jaccard formula: shared interests divided by the union of both interest lists, expressed as a percentage.
- The engine is deterministic and does not store requests or member data.
- The ranking endpoint requires a backend-held `MATCHMAKING_SERVICE_TOKEN`; it fails closed with 503 when the secret is not configured and returns 401 for missing or invalid credentials.

## Privacy and safety boundaries

- No Supabase connection or production data access.
- No private messages, photos, exact GPS coordinates, sexual orientation, or other sensitive profile attributes are processed.
- The service token is a temporary service-to-service gate, not member authentication. Store it only in a trusted backend secret manager; never put it in browser JavaScript, a mobile app, source control, or client-visible configuration.
- Before sending candidate data, the trusted application/backend must authenticate the member and enforce eligibility, blocks, consent, visibility, age restrictions, and privacy rules. This service must never bypass those controls.
- Use opaque candidate IDs only; do not send names, emails, phone numbers, or raw profiles.
- No frontend or production traffic is connected. Do not deploy this prototype as a public production API. Before staging exposure, add member-aware authorization, host/edge rate limiting, logging minimization, secret rotation, and controlled test accounts.
- Set exact browser origins in `APP_ORIGINS`. Wildcard origins are rejected. CORS is not authentication.

## Local run

```bash
python -m venv .venv
. .venv/bin/activate
pip install -r requirements-dev.txt
pytest -q
uvicorn app.main:app --reload --port 8080
```

Run commands from this directory. The service listens on port 8080 by default. The health endpoint works without the service token; ranking requests require `Authorization: Bearer <MATCHMAKING_SERVICE_TOKEN>`.

## Next milestone

Validate ranking with synthetic profiles. Then design a privacy-reviewed staging data contract and add member-aware authorization before staging integration. Production integration requires a separate review and explicit approval.
