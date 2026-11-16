"""Pure, deterministic ranking logic for user-selected interests."""

from dataclasses import dataclass


@dataclass(frozen=True)
class RankedCandidate:
    candidate_id: str
    score: int
    shared_interests: list[str]


def _normalise(values: list[str]) -> set[str]:
    return {value.strip().casefold() for value in values if value.strip()}


def rank_candidates(
    viewer_interests: list[str], candidates: list[dict[str, object]]
) -> list[RankedCandidate]:
    """Rank by Jaccard similarity; callers must filter eligible candidates first."""
    viewer = _normalise(viewer_interests)
    ranked: list[RankedCandidate] = []
    for candidate in candidates:
        candidate_id = str(candidate["candidate_id"])
        interests = _normalise(candidate["interests"])  # type: ignore[arg-type]
        shared = sorted(viewer & interests)
        union = viewer | interests
        score = round((len(shared) / len(union)) * 100) if union else 0
        ranked.append(RankedCandidate(candidate_id, score, shared))
    return sorted(ranked, key=lambda item: (-item.score, item.candidate_id))
