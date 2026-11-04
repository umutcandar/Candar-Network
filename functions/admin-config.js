"use strict";

// New-user base rates are safe only in the range supported by the reward
// calculation. Invalid input must never silently overwrite production config.
function normalizeMiningRate(raw, fallback = null) {
  const num = typeof raw === "number" ? raw
    : typeof raw === "string" && raw.trim() !== "" ? Number(raw) : NaN;
  if (!Number.isFinite(num) || num < 1 || num > 5) return fallback;
  return Math.round(num * 100) / 100;
}

module.exports = { normalizeMiningRate };
