/* The Match Intelligence Engine — phase 2
 * Ranks only candidates already approved by the existing secure Discover pipeline.
 * No database access, eligibility decisions, or private-field collection.
 */
(() => {
  "use strict";
  if (window.MatchIntelligenceEngine) return;

  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
  const score = (value) => {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? clamp(parsed, 0, 100) : 0;
  };

  function rankProfiles(profiles, preferences = {}) {
    if (!Array.isArray(profiles) || profiles.length < 2) {
      return Array.isArray(profiles) ? profiles.slice() : [];
    }

    const compatibilityWeight = 0.70;
    const lifestyleWeight = preferences.prioritiseLifestyle ? 0.20 : 0;
    const interestWeight = preferences.prioritiseSharedInterests ? 0.10 : 0;
    const totalWeight = compatibilityWeight + lifestyleWeight + interestWeight;

    return profiles.map((person, index) => {
      const compatibility = score(person?._compatibilityPercent);
      const lifestyleCount = Number(person?._lifestyleMatchCount);
      const lifestyle = clamp(
        (Number.isFinite(lifestyleCount) ? lifestyleCount : 0) / 11 * 100,
        0,
        100
      );
      const interests = score(person?._interestMatchPercent);
      const weightedRank = (
        compatibility * compatibilityWeight +
        lifestyle * lifestyleWeight +
        interests * interestWeight
      ) / totalWeight;

      // Weighted random ordering preserves discovery variety while giving
      // stronger compatibility scores a better chance of appearing first.
      const preferenceWeight = 0.5 + weightedRank / 100;
      const randomValue = Math.max(Math.random(), Number.EPSILON);
      const shuffleKey = -Math.log(randomValue) / preferenceWeight;

      return {
        person,
        index,
        weightedRank,
        shuffleKey
      };
    }).sort((a, b) => {
      const difference = a.shuffleKey - b.shuffleKey;
      return difference || a.index - b.index;
    }).map(entry => ({
      ...entry.person,
      _discoverWeightedRank: entry.weightedRank
    }));
  }

  window.MatchIntelligenceEngine = Object.freeze({
    version: "1.0-phase2",
    status: "compatibility ranking active",
    rankProfiles
  });
})();