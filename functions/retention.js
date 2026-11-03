"use strict";

function calculateStreakProgress({
  previousRewardDay,
  today,
  currentStreak,
  currentShieldCount,
}) {
  const safeStreak = Math.max(0, Math.trunc(currentStreak || 0));
  const safeShieldCount = Math.min(
    1,
    Math.max(0, Math.trunc(currentShieldCount || 0))
  );
  const streakShieldUsed =
    previousRewardDay === today - 2 &&
    safeStreak > 0 &&
    safeShieldCount > 0;
  const dailyStreak =
    previousRewardDay === today
      ? Math.max(1, safeStreak)
      : previousRewardDay === today - 1
        ? safeStreak + 1
        : streakShieldUsed
          ? safeStreak + 1
          : 1;
  let streakShieldCount = safeShieldCount - (streakShieldUsed ? 1 : 0);
  const streakShieldEarned =
    !streakShieldUsed &&
    dailyStreak > 0 &&
    dailyStreak % 7 === 0 &&
    streakShieldCount === 0;
  if (streakShieldEarned) streakShieldCount = 1;

  return {
    dailyStreak,
    streakShieldCount,
    streakShieldUsed,
    streakShieldEarned,
  };
}

module.exports = { calculateStreakProgress };
