"""HTTP wrapper around the isolated matchmaking ranking engine."""

import hmac
import os

from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.engine import rank_candidates


class CandidateInput(BaseModel):
    model_config = ConfigDict(extra="forbid")
    candidate_id: str = Field(min_length=1, max_length=80)
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
    version="0.1.0",
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
        allow_headers=["Authorization", "Content-Type"],
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


@app.post("/v1/matchmaking/rank")
async def rank(
    request: RankingRequest,
    authorization: str | None = Header(default=None),
) -> dict[str, object]:
    require_service_token(authorization)
    if not request.viewer_interests:
        raise HTTPException(status_code=422, detail="At least one viewer interest is required")
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
