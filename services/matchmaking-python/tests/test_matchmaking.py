import json
from uuid import UUID

import httpx
import pytest
from fastapi.testclient import TestClient
from fastapi import HTTPException

from app.engine import rank_candidates
from app.main import app, verify_member_and_candidates

client = TestClient(app)
VIEWER_ID = UUID("00000000-0000-4000-8000-000000000001")
CANDIDATE_ID = UUID("00000000-0000-4000-8000-000000000002")
VALID_PAYLOAD = {
    "viewer_interests": ["Music", "Travel"],
    "candidates": [{"candidate_id": str(CANDIDATE_ID), "interests": ["music", "travel"]}],
}
AUTH_HEADERS = {
    "Authorization": "Bearer service-secret",
    "X-Member-Authorization": "Bearer member-access-token",
}


def test_ranks_shared_interests_first_and_is_deterministic():
    results = rank_candidates(
        ["Music", "Travel", "Food"],
        [
            {"candidate_id": "b", "interests": ["music"]},
            {"candidate_id": "a", "interests": ["MUSIC", "travel"]},
        ],
    )
    assert [item.candidate_id for item in results] == ["a", "b"]
    assert results[0].score == 67
    assert results[0].shared_interests == ["music", "travel"]


def test_empty_interests_do_not_create_fake_matches():
    result = rank_candidates([], [{"candidate_id": "member-1", "interests": ["music"]}])[0]
    assert result.score == 0
    assert result.shared_interests == []


def test_health_endpoint():
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["service"] == "matchmaking-python"


def test_rank_endpoint_requires_service_token(monkeypatch):
    monkeypatch.setenv("MATCHMAKING_SERVICE_TOKEN", "service-secret")
    response = client.post(
        "/v1/matchmaking/rank",
        json=VALID_PAYLOAD,
        headers={"X-Member-Authorization": "Bearer member-access-token"},
    )
    assert response.status_code == 401


def test_rank_endpoint_rejects_wrong_service_token(monkeypatch):
    monkeypatch.setenv("MATCHMAKING_SERVICE_TOKEN", "service-secret")
    response = client.post(
        "/v1/matchmaking/rank",
        json=VALID_PAYLOAD,
        headers={"Authorization": "Bearer wrong-secret", "X-Member-Authorization": "Bearer member-access-token"},
    )
    assert response.status_code == 401


def test_rank_endpoint_fails_closed_when_service_token_is_unconfigured(monkeypatch):
    monkeypatch.delenv("MATCHMAKING_SERVICE_TOKEN", raising=False)
    response = client.post(
        "/v1/matchmaking/rank",
        json=VALID_PAYLOAD,
        headers={"Authorization": "Bearer service-secret", "X-Member-Authorization": "Bearer member-access-token"},
    )
    assert response.status_code == 503


def test_rank_endpoint_requires_member_session(monkeypatch):
    monkeypatch.setenv("MATCHMAKING_SERVICE_TOKEN", "service-secret")
    response = client.post(
        "/v1/matchmaking/rank",
        json=VALID_PAYLOAD,
        headers={"Authorization": "Bearer service-secret"},
    )
    assert response.status_code == 401


def test_rank_endpoint_returns_explainable_result_after_member_authorization(monkeypatch):
    async def allow_member(_token, _candidate_ids, transport=None):
        return VIEWER_ID

    monkeypatch.setenv("MATCHMAKING_SERVICE_TOKEN", "service-secret")
    monkeypatch.setattr("app.main.verify_member_and_candidates", allow_member)
    response = client.post(
        "/v1/matchmaking/rank",
        json=VALID_PAYLOAD,
        headers=AUTH_HEADERS,
    )
    assert response.status_code == 200
    assert response.json()["results"][0]["score"] == 100


def test_duplicate_candidate_ids_are_rejected(monkeypatch):
    monkeypatch.setenv("MATCHMAKING_SERVICE_TOKEN", "service-secret")
    payload = {
        "viewer_interests": ["Music"],
        "candidates": [
            {"candidate_id": str(CANDIDATE_ID), "interests": ["music"]},
            {"candidate_id": str(CANDIDATE_ID), "interests": ["travel"]},
        ],
    }
    response = client.post("/v1/matchmaking/rank", headers=AUTH_HEADERS, json=payload)
    assert response.status_code == 422


def test_unexpected_fields_are_rejected(monkeypatch):
    monkeypatch.setenv("MATCHMAKING_SERVICE_TOKEN", "service-secret")
    payload = {
        "viewer_interests": ["Music"],
        "viewer_location": {"latitude": 6.5, "longitude": 3.4},
        "candidates": [{"candidate_id": str(CANDIDATE_ID), "interests": ["music"]}],
    }
    response = client.post("/v1/matchmaking/rank", headers=AUTH_HEADERS, json=payload)
    assert response.status_code == 422


@pytest.mark.asyncio
async def test_supabase_member_and_candidate_authorization_success(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://match-project.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "publishable-test-key")
    calls = []

    async def handler(request):
        calls.append(request)
        if request.url.path == "/auth/v1/user":
            return httpx.Response(200, json={"id": str(VIEWER_ID)})
        assert request.url.path == "/rest/v1/rpc/can_interact_with_member"
        assert json.loads(request.content)["target_user_id"] == str(CANDIDATE_ID)
        return httpx.Response(200, json=True)

    transport = httpx.MockTransport(handler)
    result = await verify_member_and_candidates("member-access-token", [CANDIDATE_ID], transport)
    assert result == VIEWER_ID
    assert len(calls) == 2
    assert calls[0].headers["Authorization"] == "Bearer member-access-token"
    assert calls[1].headers["Authorization"] == "Bearer member-access-token"


@pytest.mark.asyncio
async def test_supabase_rejects_invalid_member_token(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://match-project.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "publishable-test-key")

    async def handler(_request):
        return httpx.Response(401, json={"message": "invalid token"})

    with pytest.raises(HTTPException) as error:
        await verify_member_and_candidates(
            "bad-token",
            [CANDIDATE_ID],
            httpx.MockTransport(handler),
        )
    assert error.value.status_code == 401


@pytest.mark.asyncio
async def test_supabase_denies_candidate_when_interaction_rpc_returns_false(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://match-project.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "publishable-test-key")
    calls = 0

    async def handler(request):
        nonlocal calls
        calls += 1
        if request.url.path == "/auth/v1/user":
            return httpx.Response(200, json={"id": str(VIEWER_ID)})
        return httpx.Response(200, json=False)

    with pytest.raises(HTTPException) as error:
        await verify_member_and_candidates(
            "member-access-token",
            [CANDIDATE_ID],
            httpx.MockTransport(handler),
        )
    assert error.value.status_code == 403
    assert calls == 2


@pytest.mark.asyncio
async def test_supabase_does_not_allow_member_to_rank_themselves(monkeypatch):
    monkeypatch.setenv("SUPABASE_URL", "https://match-project.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "publishable-test-key")
    calls = 0

    async def handler(_request):
        nonlocal calls
        calls += 1
        return httpx.Response(200, json={"id": str(VIEWER_ID)})

    with pytest.raises(HTTPException) as error:
        await verify_member_and_candidates(
            "member-access-token",
            [VIEWER_ID],
            httpx.MockTransport(handler),
        )
    assert error.value.status_code == 403
    assert calls == 1
