# The Match — Python matchmaking foundation

This isolated, stateless prototype ranks a caller-supplied set of eligible candidates using Jaccard similarity over interests that members explicitly choose to share.

## Current scope

- `GET /health` provides a basic health response.
- `POST /v1/matchmaking/rank` ranks 1–100 candidate records using up to 30 explicit interests per member.
- Results include shared-interest explanations.
- The engine is deterministic and does not store requests or member data.

## Privacy and safety boundaries

- No Supabase connection or production data access.
- No private messages, photos, exact GPS coordinates, sexual orientation, or other sensitive profile attributes are processed.
- Eligibility, blocks, consent, visibility, age restrictions, and privacy rules must be enforced by the trusted application/backend before candidates are sent here. This service must never bypass those controls.
- Use opaque candidate IDs only; do not send names, emails, phone numbers, or raw profiles.
- No frontend or production traffic is connected. Do not deploy this prototype as a public production API. Before staging exposure, add Supabase JWT verification, authorization, host/edge rate limiting, logging minimization, and controlled test accounts.
- Set exact browser origins in `APP_ORIGINS`. Wildcard origins are rejected. CORS is not authentication.

## Local run

```bash
python -m venv .venv
. .venv/bin/activate
pip install -r requirements-dev.txt
pytest -q
uvicorn app.main:app --reload --port 8080
```

Run commands from this directory. The service listens on port 8080 by default.

## Next milestone

Validate ranking with synthetic profiles. Then design a privacy-reviewed staging data contract and add authentication/authorization before staging integration. Production integration requires a separate review and explicit approval.
