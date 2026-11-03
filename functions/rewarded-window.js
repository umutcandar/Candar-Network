"use strict";

const DEFAULT_WINDOW_SECONDS = 24 * 60 * 60;
const DEFAULT_ATTEMPT_LIMIT = 2;
const DEFAULT_REWARDED_MULTIPLIER = 1.0;
const DEFAULT_REWARDED_MAX_MULTIPLIER = 10.0;

function getRewardedBoostState({
  nowSec,
  storedMultiplier = DEFAULT_REWARDED_MULTIPLIER,
  lastRewardAt = 0,
  windowSeconds = DEFAULT_WINDOW_SECONDS,
  maxMultiplier = DEFAULT_REWARDED_MAX_MULTIPLIER,
}) {
  // These parameters remain in the public shape for backward compatibility.
  // The earned multiplier is permanent; only ad attempts use the 24-hour window.
  void nowSec;
  void lastRewardAt;
  void windowSeconds;
  const normalizedMultiplier = Math.min(
    maxMultiplier,
    Math.max(DEFAULT_REWARDED_MULTIPLIER, Number(storedMultiplier) || DEFAULT_REWARDED_MULTIPLIER)
  );
  const active = normalizedMultiplier > DEFAULT_REWARDED_MULTIPLIER;

  return {
    active,
    multiplier: normalizedMultiplier,
    remainingSeconds: 0,
  };
}

function getActiveRewardedAttemptTimes({
  nowSec,
  firstAt = 0,
  secondAt = 0,
  legacyAttemptCount = 0,
  legacyLastAttemptAt = 0,
  successfulAttemptCount = 0,
  lastRewardAt = 0,
  windowSeconds = DEFAULT_WINDOW_SECONDS,
  limit = DEFAULT_ATTEMPT_LIMIT,
}) {
  const cutoff = nowSec - windowSeconds;
  const attempts = [firstAt, secondAt]
    .map((value) => Math.trunc(Number(value) || 0))
    .filter((value) => value > cutoff && value <= nowSec);

  const legacyTarget = Math.min(limit, Math.max(0, Math.trunc(legacyAttemptCount)));
  while (attempts.length < legacyTarget && legacyLastAttemptAt > cutoff && legacyLastAttemptAt <= nowSec) {
    attempts.push(Math.trunc(legacyLastAttemptAt));
  }

  const successfulTarget = Math.min(limit, Math.max(0, Math.trunc(successfulAttemptCount)));
  while (attempts.length < successfulTarget && lastRewardAt > cutoff && lastRewardAt <= nowSec) {
    attempts.push(Math.trunc(lastRewardAt));
  }

  return attempts.sort((a, b) => a - b).slice(-limit);
}

function getRewardedAttemptLimitState({
  attemptTimes,
  nowSec,
  windowSeconds = DEFAULT_WINDOW_SECONDS,
  limit = DEFAULT_ATTEMPT_LIMIT,
}) {
  const sorted = [...attemptTimes].sort((a, b) => a - b);
  const blocked = sorted.length >= limit;
  return {
    blocked,
    attemptCount: sorted.length,
    remainingSeconds: blocked
      ? Math.max(1, sorted[0] + windowSeconds - nowSec)
      : 0,
  };
}

function resolveRewardedAttemptForApply({
  attemptTimes,
  requestedAttemptAt = 0,
  lastAppliedAttemptAt = 0,
}) {
  const normalizedAttempts = [...attemptTimes]
    .map((value) => Math.trunc(Number(value) || 0))
    .filter((value) => value > 0);
  const requested = Math.trunc(Number(requestedAttemptAt) || 0);
  const attemptAt = requested > 0
    ? requested
    : normalizedAttempts.reduce((latest, value) => Math.max(latest, value), 0);
  const lastApplied = Math.trunc(Number(lastAppliedAttemptAt) || 0);

  return {
    valid: attemptAt > 0 && normalizedAttempts.includes(attemptAt),
    idempotent: attemptAt > 0 && attemptAt <= lastApplied,
    attemptAt,
  };
}

module.exports = {
  DEFAULT_ATTEMPT_LIMIT,
  DEFAULT_REWARDED_MAX_MULTIPLIER,
  DEFAULT_REWARDED_MULTIPLIER,
  DEFAULT_WINDOW_SECONDS,
  getActiveRewardedAttemptTimes,
  getRewardedBoostState,
  getRewardedAttemptLimitState,
  resolveRewardedAttemptForApply,
};
