from fastapi.testclient import TestClient
from app.engine import rank_candidates
from app.main import app

client = TestClient(app)


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


def test_rank_endpoint_returns_explainable_result():
    response = client.post("/v1/matchmaking/rank", json={
        "viewer_interests": ["Music", "Travel"],
        "candidates": [{"candidate_id": "member-1", "interests": ["music", "travel"]}],
    })
    assert response.status_code == 200
    assert response.json()["results"][0]["score"] == 100


def test_duplicate_candidate_ids_are_rejected():
    response = client.post("/v1/matchmaking/rank", json={
        "viewer_interests": ["Music"],
        "candidates": [
            {"candidate_id": "same", "interests": ["music"]},
            {"candidate_id": "same", "interests": ["travel"]},
        ],
    })
    assert response.status_code == 422


def test_unexpected_fields_are_rejected():
    response = client.post("/v1/matchmaking/rank", json={
        "viewer_interests": ["Music"],
        "viewer_location": {"latitude": 6.5, "longitude": 3.4},
        "candidates": [{"candidate_id": "member-1", "interests": ["music"]}],
    })
    assert response.status_code == 422
