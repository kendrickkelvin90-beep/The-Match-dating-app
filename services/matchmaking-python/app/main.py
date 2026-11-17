"""HTTP wrapper around the isolated matchmaking ranking engine."""

import hmac
import os
from uuid import UUID

import httpx
from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.engine import rank_candidates


class CandidateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    candidate_id: UUID
    interests: list[str] = Field(default_factory=list, max_length=30)

    @field_validator("interests")
    @classmethod
    def validate_interests(cls, values: list[str]) -> list[str]:
        cleaned = [value.strip() for value in values]
        if any(not value or len(value) > 40 for value in cleaned):
            raise ValueError("Each interest must contain 1 to 40 characters")
        return cleaned


class RankingRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    viewer_interests: list[str] = Field(default_factory=list, max_length=30)
    candidates: list[CandidateInput] = Field(min_length=1, max_length=100)

    @field_validator("viewer_interests")
    @classmethod
    def validate_viewer_interests(cls, values: list[str]) -> list[str]:
        cleaned = [value.strip() for value in values]
        if any(not value or len(value) > 40 for value in cleaned):
            raise ValueError("Each interest must contain 1 to 40 characters")
        return cleaned

    @field_validator("candidates")
    @classmethod
    def unique_candidate_ids(cls, values: list[CandidateInput]) -> list[CandidateInput]:
        ids = [candidate.candidate_id for candidate in values]
        if len(ids) != len(set(ids)):
            raise ValueError("Candidate IDs must be unique")
        return values


app = FastAPI(
    title="The Match — Matchmaking Service",
    version="0.2.0",
    docs_url=None,
    redoc_url=None,
)
allowed_origins = [
    item.strip()
    for item in os.getenv("APP_ORIGINS", "").split(",")
    if item.strip()
]
if "*" in allowed_origins:
    raise RuntimeError("Wildcard CORS origins are not allowed")
if allowed_origins:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=allowed_origins,
        allow_credentials=False,
        allow_methods=["POST"],
        allow_headers=["Authorization", "Content-Type", "X-Member-Authorization"],
        max_age=600,
    )


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "matchmaking-python"}


def require_service_token(authorization: str | None) -> None:
    """Require a backend-held service token; never expose it to browser clients."""
    expected = os.getenv("MATCHMAKING_SERVICE_TOKEN", "")
    if not expected:
        raise HTTPException(
            status_code=503,
            detail="Matchmaking service authentication is not configured",
        )

    scheme, separator, supplied = (authorization or "").partition(" ")
    if (
        not separator
        or scheme.casefold() != "bearer"
        or not supplied.strip()
        or not hmac.compare_digest(supplied.strip(), expected)
    ):
        raise HTTPException(status_code=401, detail="Service authentication required")


def extract_bearer_token(authorization: str | None) -> str:
    scheme, separator, token = (authorization or "").partition(" ")
    if not separator or scheme.casefold() != "bearer" or not token.strip():
        raise HTTPException(status_code=401, detail="A valid member session is required")
    return token.strip()


async def verify_member_and_candidates(
    member_token: str,
    candidate_ids: list[UUID],
    transport: httpx.AsyncBaseTransport | None = None,
) -> UUID:
    """Verify the member with Supabase Auth and enforce the app's existing interaction RPC."""
    supabase_url = os.getenv("SUPABASE_URL", "").rstrip("/")
    supabase_anon_key = os.getenv("SUPABASE_ANON_KEY", "")
    if not supabase_url or not supabase_anon_key:
        raise HTTPException(
            status_code=503,
            detail="Member authorization is not configured",
        )

    headers = {
        "apikey": supabase_anon_key,
        "Authorization": f"Bearer {member_token}",
    }

    try:
        async with httpx.AsyncClient(timeout=8.0, transport=transport) as client:
            auth_response = await client.get(
                f"{supabase_url}/auth/v1/user",
                headers=headers,
            )
            if auth_response.status_code in (401, 403):
                raise HTTPException(status_code=401, detail="Member session is invalid")
            if not auth_response.is_success:
                raise HTTPException(status_code=503, detail="Member authorization is temporarily unavailable")

            try:
                viewer_id = UUID(auth_response.json()["id"])
            except (KeyError, TypeError, ValueError):
                raise HTTPException(status_code=503, detail="Member identity could not be verified")

            for candidate_id in candidate_ids:
                if candidate_id == viewer_id:
                    raise HTTPException(status_code=403, detail="One or more candidates are not eligible")

                rpc_response = await client.post(
                    f"{supabase_url}/rest/v1/rpc/can_interact_with_member",
                    headers=headers,
                    json={"target_user_id": str(candidate_id)},
                )
                if rpc_response.status_code in (401, 403):
                    raise HTTPException(status_code=401, detail="Member session is invalid")
                if not rpc_response.is_success:
                    raise HTTPException(status_code=503, detail="Candidate eligibility could not be verified")
                try:
                    allowed = rpc_response.json()
                except ValueError:
                    raise HTTPException(status_code=503, detail="Candidate eligibility could not be verified")
                if allowed is not True:
                    raise HTTPException(status_code=403, detail="One or more candidates are not eligible")

            return viewer_id
    except httpx.RequestError:
        raise HTTPException(status_code=503, detail="Member authorization is temporarily unavailable")


@app.post("/v1/matchmaking/rank")
async def rank(
    request: RankingRequest,
    authorization: str | None = Header(default=None),
    member_authorization: str | None = Header(default=None, alias="X-Member-Authorization"),
) -> dict[str, object]:
    # Both credentials are required: a trusted backend service credential and
    # the actual member's Supabase access token forwarded by that backend.
    require_service_token(authorization)
    member_token = extract_bearer_token(member_authorization)
    if not request.viewer_interests:
        raise HTTPException(status_code=422, detail="At least one viewer interest is required")

    await verify_member_and_candidates(
        member_token,
        [candidate.candidate_id for candidate in request.candidates],
    )

    results = rank_candidates(
        request.viewer_interests,
        [item.model_dump() for item in request.candidates],
    )
    return {
        "results": [
            {
                "candidate_id": item.candidate_id,
                "score": item.score,
                "shared_interests": item.shared_interests,
            }
            for item in results
        ]
    }
